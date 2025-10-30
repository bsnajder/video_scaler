-------------------------------------------------------------------------------
-- Video Scaler IP - FPGA-based Video Scaling Solution
-------------------------------------------------------------------------------
-- Copyright (c) 2025 Boris Snajder
-- 
-- This source describes Open Hardware and is licensed under the CERN-OHL-P v2
-- 
-- You may redistribute and modify this source and make products using it under
-- the terms of the CERN-OHL-P v2 (https://ohwr.org/cern_ohl_p_v2.txt).
-- 
-- This source is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,
-- INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A
-- PARTICULAR PURPOSE. Please see the CERN-OHL-P v2 for applicable conditions.
-- 
-- Source location: https://github.com/bsnajder/video_scaler
-------------------------------------------------------------------------------
-- File: scale_fsm_vert.vhd
-- Description: Vertical scaling finite state machine for video scaler IP.
--              Implements vertical interpolation with line buffering, configurable
--              scaling ratios, and frame mirroring for edge handling.
-- Author: Boris Snajder
-- Created: 2025
-- Modified: 2025-09-20
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.std_logic_misc.all;

library utils;
use utils.utils_pkg.all;

library scale_ip;
use scale_ip.scale_pkg.all;

entity scale_fsm_vert is
    port ( 
	    clk                 : in std_logic;
	    rst                 : in std_logic;
        --
        vert_res            : in std_logic_vector(15 downto 0);
        vert_scale          : in std_logic_vector(31 downto 0);
    	--
    	axis_tvalid_s_i     : in std_logic;
    	axis_tready_s_o     : out std_logic;
    	axis_tdata_s_i      : in std_logic_vector(ENG_NUM*3*8-1 downto 0);
    	axis_tlast_s_i      : in std_logic;
        axis_tstrobe_s_i    : in std_logic_vector(ENG_NUM*3-1 downto 0);
    	axis_tuser_s_i      : in std_logic_vector(0 downto 0);
	    --
        m_axis_tdata_m_o    : out std_logic_vector(ENG_NUM*3*8-1 downto 0);
        m_axis_tvalid_m_o   : out std_logic;
        m_axis_tready_m_i   : in std_logic;
        m_axis_tlast_m_o    : out std_logic;
        m_axis_tstrobe_m_o  : out std_logic_vector(ENG_NUM*3-1 downto 0);
        m_axis_tuser_m_o    : out std_logic_vector(0 downto 0)
    );
end scale_fsm_vert;

architecture rtl of scale_fsm_vert is

    signal scale_cnt_inc    : unsigned(SCALE_CNT_SIZE-1 downto 0) := to_unsigned(7294442, SCALE_CNT_SIZE); --scale 0.575

    type vert_fsm_t is 
    (
        WAIT_START_s, 
        START_s,
        SCALE_s,
        FLUSH_s,
        TUSER_TERMINATE_s,
        DONE_s
    );

    signal vert_fsm_cs      : vert_fsm_t;
    signal vert_fsm_ns      : vert_fsm_t;

    signal axis_tready_s_int : std_logic;

    signal line_cnt         : unsigned(16 downto 0);
    signal line_start_cnt   : unsigned(4 downto 0);
    signal line_done        : std_logic;
    signal line_wr_ptr      : unsigned(log2(TAP_NUM) downto 0);
    signal line_center_ptr  : unsigned(log2(TAP_NUM) downto 0);
    signal line_last_ptr    : unsigned(log2(TAP_NUM) downto 0);
    signal line_last_valid  : std_logic;
    signal wr_en            : std_logic_vector(TAP_NUM downto 0);
    signal wr_line_active   : std_logic_vector(TAP_NUM downto 0);
    signal first_pix        : std_logic;

    signal hor_res          : unsigned(15 downto 0);
    signal hor_res_latch    : std_logic;
    signal hor_strobe_latch : std_logic_vector(ENG_NUM-1 downto 0);

    signal wr_addr          : unsigned(log2(LINE_SIZE/ENG_NUM)-1 downto 0);
    signal wr_data          : std_logic_vector(ENG_NUM*3*8-1 downto 0);
    signal rd_addr          : unsigned(log2(LINE_SIZE/ENG_NUM)-1 downto 0);
    type rd_data_t          is array (integer range <>) of std_logic_vector(ENG_NUM*3*8-1 downto 0);
    signal rd_data          : rd_data_t(0 to TAP_NUM);
    signal rd_data_eng      : rd_data_t(0 to TAP_NUM-1);
    type eng_data_t         is array (integer range <>) of std_logic_vector(3*TAP_NUM*8-1 downto 0);
    signal eng_data         : eng_data_t(ENG_NUM-1 downto 0);


    type line_stat_t is record
        valid       : std_logic;
        last        : std_logic;
    end record line_stat_t;

    type line_stat_arr_t is array (0 to TAP_NUM) of line_stat_t;
    signal line_stat : line_stat_arr_t;

    constant LINE_STAT_DEFAULT : line_stat_t := (valid => '0', last => '0');

    signal scale_run         : std_logic;
    signal scale_not_done    : std_logic;
    signal scale_last        : std_logic;
    signal scale_last_d      : std_logic;
    signal scale_cnt         : unsigned(SCALE_CNT_SIZE-1 downto 0);
    signal scale_cnt_next    : unsigned(SCALE_CNT_SIZE-1 downto 0);
    signal scale_phase       : std_logic_vector(log2(PHASE_NUM)-1 downto 0);

    signal scale_dvalid_in   : std_logic_vector(ENG_NUM-1 downto 0);
    signal scale_dvalid_in_d : std_logic_vector(ENG_NUM-1 downto 0);
    signal scale_last_in     : std_logic_vector(ENG_NUM-1 downto 0);
    signal scale_last_in_d   : std_logic_vector(ENG_NUM-1 downto 0);
    signal scale_user_in     : std_logic_vector(ENG_NUM-1 downto 0);
    signal scale_user_in_d   : std_logic_vector(ENG_NUM-1 downto 0);

    signal scale_dvalid_out  : std_logic_vector(ENG_NUM-1 downto 0);
    signal scale_last_out    : std_logic_vector(ENG_NUM-1 downto 0);
    signal scale_user_out    : std_logic_vector(ENG_NUM-1 downto 0);
    type scale_data_t        is array (integer range <>) of std_logic_vector(8*3-1 downto 0);
    signal scale_data_out    : scale_data_t(ENG_NUM-1 downto 0);


    type scale_run_ctrl_t is
    (
        SCALE_WAIT_s,
        SCALE_RUN_s,
        SCALE_SKIP_s
    );

    signal scale_run_ctrl_cs    : scale_run_ctrl_t;
    signal scale_run_ctrl_ns    : scale_run_ctrl_t;

    signal data_rdy             : std_logic;
    signal data_rdy_valid       : std_logic;
    signal scale_flush_phase    : std_logic;

    signal out_fifo_afull       : std_logic := '0';
    signal out_fifo_empty       : std_logic := '0';
    signal out_fifo_wren        : std_logic;
    signal out_fifo_wrdata      : std_logic_vector(ENG_NUM*8*3+ENG_NUM+2-1 downto 0);
    signal out_fifo_rddata      : std_logic_vector(ENG_NUM*8*3+ENG_NUM+2-1 downto 0);
    signal out_fifo_valid       : std_logic;

    type tap_ptr_t is array (integer range <>) of std_logic_vector(log2(TAP_NUM)-1 downto 0);
    signal tap_ptr             : tap_ptr_t(TAP_NUM-1 downto 0);

    subtype line_ptr_t is integer range 0 to 6;

    function get_tap_ptr( tap_index      : integer; 
                          center_ptr     : unsigned(log2(TAP_NUM) downto 0);
                          last_ptr       : unsigned(log2(TAP_NUM) downto 0);
                          last_val       : std_logic) 
    return std_logic_vector is
        variable ptr_helper               : unsigned(log2(TAP_NUM)+1 downto 0); --TODO do I need more bits here?
        variable center_last_diff         : unsigned(log2(TAP_NUM)+1 downto 0);
        variable center_last_diff_inverse : unsigned(log2(TAP_NUM)+1 downto 0);
        variable last_effective           : std_logic;
        variable tap_off_helper : integer;
    begin

        last_effective := '0';
        if last_val = '1' then
            center_last_diff := resize(last_ptr, center_last_diff'length) - resize(center_ptr, center_last_diff'length);
            if center_last_diff(center_last_diff'left) = '1' then --ptr_helper is negative, handle wrap around
                center_last_diff := (TAP_NUM + 1) + center_last_diff;
            end if;

            -- calculate how many pixels we need to mirror
            center_last_diff_inverse := TAP_CENTER + 1 - center_last_diff; --range of this should bi in interval 0 to TAP_CENTER 
            if center_last_diff_inverse /= to_unsigned(0, center_last_diff_inverse'length) and center_last_diff_inverse(center_last_diff_inverse'left) = '0' then 
                last_effective := '1'; --indicate we will need to mirror pixels
            end if;
        end if;

        if tap_index = TAP_CENTER then
            ptr_helper := resize(center_ptr, ptr_helper'length);
        elsif tap_index > TAP_CENTER then
            ptr_helper := resize(center_ptr, ptr_helper'length) + (tap_index - TAP_CENTER);
            if last_effective = '1' then

                for i in 0 to TAP_CENTER loop
                    if TAP_NUM - tap_index + i = to_integer(center_last_diff_inverse) then
                        ptr_helper := ptr_helper - shift_left(to_unsigned(i+1, ptr_helper'length), 1);
                    end if;
                end loop;        
            end if;

        elsif tap_index < TAP_CENTER then
            ptr_helper := resize(center_ptr, ptr_helper'length) - (TAP_CENTER - tap_index);
        end if;

        if ptr_helper(ptr_helper'left) = '1' then --ptr_helper is negative
            ptr_helper := (TAP_NUM + 1) + ptr_helper;
        elsif ptr_helper > TAP_NUM then
            ptr_helper := ptr_helper - (TAP_NUM + 1);
        end if;

        return std_logic_vector(ptr_helper(log2(TAP_NUM)-1 downto 0));

    end function;
    
begin

    scale_cnt_inc <= resize(unsigned(vert_scale), scale_cnt_inc'length);

    process(line_wr_ptr, line_stat, vert_fsm_cs)
    begin
        axis_tready_s_int <= '0';
        if vert_fsm_cs = START_s or vert_fsm_cs = SCALE_s then
            for i in 0 to TAP_NUM loop
                if line_wr_ptr = to_unsigned(i, line_wr_ptr'length) then
                    if line_stat(i).valid = '0' then
                        axis_tready_s_int <= '1';
                    end if;
                end if;
            end loop;
        end if;
    end process;

    axis_tready_s_o <= '1' when (vert_fsm_cs = WAIT_START_s and vert_fsm_ns = WAIT_START_s) else axis_tready_s_int;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                vert_fsm_cs <= WAIT_START_s;
            else
                vert_fsm_cs <= vert_fsm_ns;
            end if;
        end if;
    end process;


    process(vert_fsm_cs, axis_tvalid_s_i, axis_tlast_s_i, axis_tstrobe_s_i, axis_tuser_s_i, line_done, line_wr_ptr, line_start_cnt, line_cnt, scale_last, scale_not_done, line_center_ptr, line_stat, scale_run_ctrl_cs, first_pix)
        variable flush_done : std_logic;
    begin
        case vert_fsm_cs is
            when WAIT_START_s =>
                if axis_tvalid_s_i = '1' and axis_tuser_s_i = "1" then
                    vert_fsm_ns <= START_s;
                else
                    vert_fsm_ns <= WAIT_START_s;
                end if;

            when START_s =>
                if axis_tvalid_s_i = '1' and axis_tlast_s_i = '1' and line_start_cnt(line_start_cnt'left) = '1' then
                    vert_fsm_ns <= SCALE_s;
                elsif axis_tvalid_s_i = '1' and axis_tuser_s_i = "1" and axis_tready_s_int = '1' and first_pix = '0' then
                    vert_fsm_ns <= TUSER_TERMINATE_s;                    
                else
                    vert_fsm_ns <= START_s;
                end if;

            when SCALE_s =>
                if axis_tvalid_s_i = '1' and axis_tlast_s_i = '1' and line_cnt = to_unsigned(0, line_cnt'length) then
                    vert_fsm_ns <= FLUSH_s;
                elsif axis_tvalid_s_i = '1' and axis_tuser_s_i = "1" then
                    vert_fsm_ns <= TUSER_TERMINATE_s;
                else
                    vert_fsm_ns <= SCALE_s;
                end if;

            when FLUSH_s =>
                if scale_last = '1' and scale_not_done = '0' then
                    flush_done := '0';
                    for i in 0 to TAP_NUM loop
                        if line_center_ptr = to_unsigned(i, line_wr_ptr'length) and line_stat(i).last = '1' then
                            flush_done := '1';
                        end if;
                    end loop;
                    if flush_done = '1' then
                        vert_fsm_ns <= DONE_s;
                    else
                        vert_fsm_ns <= FLUSH_s;
                    end if;
                else
                    vert_fsm_ns <= FLUSH_s;
                end if;

            when TUSER_TERMINATE_s =>
                if scale_run_ctrl_cs = SCALE_WAIT_s then
                    vert_fsm_ns <= DONE_s;
                else
                    vert_fsm_ns <= TUSER_TERMINATE_s;
                end if;

            when DONE_s =>
                vert_fsm_ns <= WAIT_START_s;

            when others =>
                vert_fsm_ns <= WAIT_START_s;

        end case;
    end process;

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
               first_pix <= '1';
            else
               if vert_fsm_cs = WAIT_START_s then
                   first_pix <= '1';
                elsif vert_fsm_cs = START_s then
                    if axis_tvalid_s_i = '1' and axis_tready_s_int = '1' then
                        first_pix <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    p_line_stat: process(clk)
        variable line_done_ptr_v : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                for i in 0 to TAP_NUM loop
                    line_stat(i) <= LINE_STAT_DEFAULT;
                end loop;
                line_start_cnt <= to_unsigned(TAP_NUM/2-1, line_start_cnt'length);
                line_cnt <= (others => '0');
                line_wr_ptr <= to_unsigned(0, line_wr_ptr'length);
                wr_line_active <= (others => '0');
                line_last_valid <= '0';

            else
                if vert_fsm_cs = WAIT_START_s then
                    for i in 0 to TAP_NUM loop
                        line_stat(i) <= LINE_STAT_DEFAULT;
                    end loop;
                    line_cnt <= resize(unsigned(vert_res), line_cnt'length) - 1;
                    line_wr_ptr <= to_unsigned(0, line_wr_ptr'length);
                    line_start_cnt <= to_unsigned(TAP_NUM/2-1, line_start_cnt'length);

                    if vert_fsm_ns /= WAIT_START_s then
                        wr_line_active <= (0 => '1', others => '0');
                    else
                        wr_line_active <= (others => '0');
                    end if;
                    line_last_valid <= '0';

                elsif vert_fsm_cs = START_s then
                    if axis_tvalid_s_i = '1' and axis_tlast_s_i = '1' then
                        line_start_cnt <= line_start_cnt - 1;
                        line_cnt <= line_cnt - 1;
                        line_wr_ptr <= line_wr_ptr + 1;

                        for i in 0 to TAP_NUM/2 loop
                            if line_wr_ptr = to_unsigned(i, line_wr_ptr'length) then
                                line_stat(i).valid <= '1';
                                wr_line_active(i) <= '0';
                                wr_line_active(i+1) <= '1';

                                --handle mirroring
                                if i > 0 and i < TAP_NUM/2 then --lines 1 .. TAP_NUM/2-1
                                    line_stat(TAP_NUM-i+1).valid <= '1';
                                end if;

                                if i = 0 then --lines 0 .. TAP_NUM/2-1
                                    wr_line_active(TAP_NUM) <= '1';
                                elsif i > 0 and i < TAP_NUM/2-1 then
                                    wr_line_active(TAP_NUM-i+1) <= '0';
                                    wr_line_active(TAP_NUM-i) <= '1';
                                elsif i = TAP_NUM/2-1 then
                                    wr_line_active(TAP_NUM downto TAP_NUM/2+1) <= (others => '0');
                                end if;

                            end if;
                        end loop;
                    end if;

                elsif vert_fsm_cs = SCALE_s then

                    if scale_last = '1' and scale_not_done = '0' then
                        for i in 0 to TAP_NUM loop
                            if line_center_ptr = to_unsigned(i, line_center_ptr'length) then
                                if i < TAP_NUM/2-1 then
                                    line_done_ptr_v := TAP_NUM - (TAP_NUM/2-1) + 1 + i;
                                else
                                    line_done_ptr_v := i - (TAP_NUM/2-1);
                                end if;
                                line_stat(line_done_ptr_v).valid <= '0';
                            end if;
                        end loop;
                    end if;


                    if axis_tvalid_s_i = '1' and axis_tlast_s_i = '1' then

                        line_cnt <= line_cnt - 1;
                        for i in 0 to TAP_NUM loop
                            if line_wr_ptr = to_unsigned(i, line_wr_ptr'length) then
                                line_stat(i).valid <= '1';
                                if line_cnt = to_unsigned(0, line_cnt'length) then
                                    line_stat(i).last <= '1';
                                    line_last_ptr <= to_unsigned(i, line_last_ptr'length);
                                    line_last_valid <= '1';
                                else
                                    line_stat(i).last <= '0';
                                end if;

                                if i = TAP_NUM then
                                    wr_line_active <= (0 => '1', others => '0');
                                else
                                    wr_line_active(i+1) <= '1';
                                    wr_line_active(i) <= '0';
                                end if;
                            end if;
                        end loop;
                        if line_wr_ptr = to_unsigned(TAP_NUM, line_wr_ptr'length) then
                            line_wr_ptr <= to_unsigned(0, line_wr_ptr'length);
                        else
                            line_wr_ptr <= line_wr_ptr + 1;

                        end if;
                    end if;

                elsif vert_fsm_cs = FLUSH_s then
                    wr_line_active <= (others => '0');

                end if;
            end if;
        end if;
    end process p_line_stat;


    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                wr_addr <= (others => '0');
            else
                if vert_fsm_cs = WAIT_START_s or vert_fsm_cs = DONE_s then
                    wr_addr <= (others => '0');
                end if;

                if axis_tvalid_s_i = '1' and axis_tready_s_int = '1' then
                    if axis_tlast_s_i = '1' then
                        wr_addr <= (others => '0');
                    else
                        wr_addr <= wr_addr + 1;
                    end if;
                end if;
                
            end if;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                hor_res <= (others => '0');
                hor_res_latch <= '0';
            else
                if vert_fsm_cs = WAIT_START_s then
                    hor_res <= (others => '0');
                    hor_res_latch <= '0';

                elsif vert_fsm_cs = START_s then
                    if axis_tvalid_s_i = '1' and axis_tready_s_int = '1' and hor_res_latch = '0' then
                        hor_res <= hor_res + 1;
                        if axis_tlast_s_i = '1' then
                            hor_res_latch <= '1';
                            for i in 0 to ENG_NUM-1 loop
                                hor_strobe_latch(i) <= axis_tstrobe_s_i(i*3); --if pixels have 3bytes (RGB), we need to check appropriate byte valid
                            end loop; 
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;


    wr_data <= axis_tdata_s_i;

    u_mem_gen: for i in 0 to TAP_NUM generate
        
        wr_en(i) <= axis_tvalid_s_i and axis_tready_s_int and wr_line_active(i);

        u_line_mem: entity utils.sdp_bram
        generic map(
            WDWIDTH		 => ENG_NUM*8*3,
            RDWIDTH		 => ENG_NUM*8*3,
            WDEPTH		 => LINE_SIZE/ENG_NUM
        )
        port map(
            clka 		=> clk,
            ena 		=> '1',
            wea 		=> wr_en(i),
            addra 		=> std_logic_vector(wr_addr),
            dina 		=> wr_data,
            clkb 		=> clk,
            enb 		=> '1',
            addrb 		=> std_logic_vector(rd_addr),
            doutb 		=> rd_data(i)
        );


    end generate;

    gen_eng_data: for i in 0 to TAP_NUM-1 generate

        process(rd_data, line_center_ptr, tap_ptr)
        begin
            rd_data_eng(i) <= rd_data(to_integer(unsigned(tap_ptr(i))));
        end process;

    end generate;


    process(clk)
       variable scale_cnt_next_v        : unsigned(SCALE_CNT_SIZE-1 downto 0);
       variable scaler_run_v            : std_logic;
       variable scaler_not_done_v       : std_logic;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                scale_run       <= '0';
                scale_not_done  <= '0';
                scale_cnt       <= (others => '0');
                scale_cnt_next  <= (others => '0');
            else
                if vert_fsm_cs = START_s then
                    scale_cnt <= (others => '0');
                    scale_run <= '0';
                    scale_not_done <= '0';
                    if vert_fsm_ns /= START_s then
                        calc_next_phase(scale_cnt, scale_cnt_inc, scale_cnt_next_v, scaler_run_v, scaler_not_done_v);
                        scale_cnt_next <= scale_cnt_next_v;
                        scale_run <= scaler_run_v;
                        scale_not_done <= scaler_not_done_v;
                    end if;

                elsif vert_fsm_cs = SCALE_s or vert_fsm_cs = FLUSH_s then
                    if scale_last = '1' then
                        scale_cnt <= scale_cnt_next;
                        calc_next_phase(scale_cnt_next, scale_cnt_inc, scale_cnt_next_v, scaler_run_v, scaler_not_done_v);
                        scale_cnt_next <= scale_cnt_next_v;
                        scale_run <= scaler_run_v;
                        scale_not_done <= scaler_not_done_v;
                    end if;

                end if;

            end if;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                scale_run_ctrl_cs <= SCALE_WAIT_s;
            else
                scale_run_ctrl_cs <= scale_run_ctrl_ns;
            end if;
        end if;
    end process;

    process(scale_run, scale_run_ctrl_cs, data_rdy, scale_last, vert_fsm_cs)
    begin
        case scale_run_ctrl_cs is
            when SCALE_WAIT_s =>
                if data_rdy = '1' and (vert_fsm_cs = SCALE_s or vert_fsm_cs = FLUSH_s) then
                    if scale_run = '1' then
                        scale_run_ctrl_ns <= SCALE_RUN_s;
                    else
                        scale_run_ctrl_ns <= SCALE_SKIP_s;
                    end if;
                else
                    scale_run_ctrl_ns <= SCALE_WAIT_s;
                end if;

            when SCALE_RUN_s =>
                if scale_last = '1' then
                    scale_run_ctrl_ns <= SCALE_WAIT_s;
                else
                    scale_run_ctrl_ns <= SCALE_RUN_s;
                end if;

            when SCALE_SKIP_s =>
                if scale_last = '1' then
                    scale_run_ctrl_ns <= SCALE_WAIT_s;
                else
                    scale_run_ctrl_ns <= SCALE_SKIP_s;
                end if;


            when others =>
                scale_run_ctrl_ns <= SCALE_WAIT_s;

        end case;
    end process;

    process(clk)
        variable last_line_v : integer;
        variable data_rdy_v  : std_logic;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                line_center_ptr <= to_unsigned(0, line_center_ptr'length);
                data_rdy <= '0';
                scale_flush_phase <= '0';

            else
                if vert_fsm_cs = START_s then
                    line_center_ptr <= to_unsigned(0, line_center_ptr'length);
                    data_rdy <= '0';
                    scale_flush_phase <= '0';
                else
                
                    if scale_run_ctrl_cs = SCALE_WAIT_s then
                        data_rdy_v  := '0';
                        for i in 0 to TAP_NUM loop
                            if line_center_ptr = to_unsigned(i, line_center_ptr'length) then
                                if i <= TAP_NUM/2 then
                                    data_rdy_v := line_stat(i+TAP_NUM/2).valid;
                                else
                                    data_rdy_v := line_stat(i-(TAP_NUM/2+1)).valid;
                                end if;
                            end if;
                        end loop;
                        if vert_fsm_cs = DONE_s then
                            data_rdy_v := '0';
                        end if;
                        if scale_flush_phase = '1' then
                            data_rdy_v := '1';
                        end if;
                        data_rdy <= data_rdy_v;
                    end if;

                    if scale_last = '1' then
                        if scale_not_done = '1' then
                        else --we are done
                            if line_center_ptr = to_unsigned(TAP_NUM, line_center_ptr'length) then
                                line_center_ptr <= to_unsigned(0, line_center_ptr'length);
                            else
                                line_center_ptr <= line_center_ptr + 1;
                            end if;
                            if vert_fsm_cs = FLUSH_s then
                                scale_flush_phase <= '1';
                            else
                                scale_flush_phase <= '0';
                            end if;
                        end if;
                    end if;


                end if;

            end if;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tap_ptr <= (others => (others => '0'));
            else
                if scale_run_ctrl_cs = SCALE_WAIT_s then
                    for i in 0 to TAP_NUM-1 loop
                        tap_ptr(i) <= get_tap_ptr(i, line_center_ptr, line_last_ptr, line_last_valid);
                    end loop;
                end if;
            end if;
        end if;
    end process;

    process (clk)
        variable hor_done_helper : unsigned(15 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                rd_addr      <= (others => '0');
                scale_last   <= '0';
                scale_last_d <= '0';
                scale_dvalid_in   <= (others => '0');
                scale_dvalid_in_d <= (others => '0');
                scale_last_in     <= (others => '0');
                scale_last_in_d   <= (others => '0');
                scale_user_in     <= (others => '0');
                scale_user_in_d   <= (others => '0');

            else
                scale_dvalid_in_d <= scale_dvalid_in;
                scale_last_in_d <= scale_last_in;
                scale_user_in_d <= scale_user_in;

                if vert_fsm_cs = START_s then
                    rd_addr <= (others => '0');
                    scale_last <= '0';
                    scale_dvalid_in <= (others => '0');
                    scale_dvalid_in_d <= (others => '0');
                    scale_last_in <= (others => '0');
                    scale_last_in_d <= (others => '0');
                    scale_user_in <= (others => '1');
                end if;

                scale_last <= '0';

                if scale_run_ctrl_cs = SCALE_WAIT_s then
                    rd_addr <= (others => '0');
                    scale_dvalid_in <= (others => '0');
                    if scale_run_ctrl_ns = SCALE_RUN_s then
                        scale_dvalid_in <= (others => '1');
                    end if;
                    scale_last_in <= (others => '0');

                elsif scale_run_ctrl_cs = SCALE_RUN_s then
                    scale_user_in <= (others => '0');

                    if out_fifo_afull = '0' then

                        rd_addr <= rd_addr + 1;
                        scale_dvalid_in <= (others => '1');
                        hor_done_helper := hor_res - resize(unsigned(rd_addr), hor_res'length) - 2;
                        if hor_done_helper(hor_done_helper'left) = '1' and scale_run_ctrl_ns = SCALE_RUN_s then
                            scale_last <= '1';
                        else
                            scale_last <= '0';
                        end if;

                        if hor_done_helper(hor_done_helper'left) = '1' then
                            scale_dvalid_in <= (others => '0');
                        end if;

                        if hor_done_helper = to_unsigned(0, hor_done_helper'length) then
                            scale_last_in <= (others => '1');
                            scale_dvalid_in <= hor_strobe_latch; 
                        else
                            scale_last_in <= (others => '0');
                        end if;

                    else
                        scale_dvalid_in <= (others => '0');

                    end if;
                elsif scale_run_ctrl_cs = SCALE_SKIP_s then
                    scale_dvalid_in <= (others => '0');
                    scale_last_in <= (others => '0');
                    if scale_last = '0' then
                        scale_last <= '1';
                    end if;


                end if;
                scale_last_d <= scale_last;
            end if;
        end if;
    end process;

    p_phase: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                scale_phase <= (others => '0');
            else
                if scale_run_ctrl_cs = SCALE_WAIT_s then
                    scale_phase <= std_logic_vector(scale_cnt(SCALE_CNT_FRAC_SIZE-1 downto SCALE_CNT_FRAC_SIZE-scale_phase'length));
                end if;
            end if;
        end if;
    end process p_phase;

    gen_eng: for i in 0 to ENG_NUM-1 generate


        gen_eng_data_vector: for tap_idx in 0 to TAP_NUM-1 generate
            gen_col_comp: for col_idx in 0 to 2 generate
                eng_data(i)((col_idx*TAP_NUM+tap_idx+1)*8-1 downto (col_idx*TAP_NUM+tap_idx)*8) <= rd_data_eng(tap_idx)((i*3+col_idx+1)*8-1 downto (i*3+col_idx)*8);
            end generate;
        end generate;

        u_eng: entity scale_ip.scale_eng
        port map(
                clk            => clk,
                rst            => rst,
                --
                data_in        => eng_data(i),
                data_in_val    => scale_dvalid_in_d(i),
                data_in_last   => scale_last_in_d(i),
                data_in_user   => scale_user_in_d(i),
                phase_in       => scale_phase,

                data_out       => scale_data_out(i),
                data_out_val   => scale_dvalid_out(i),
                data_out_user  => scale_user_out(i),
                data_out_last  => scale_last_out(i)

            );
    end generate;

    out_fifo_wren <= scale_dvalid_out(0);
    out_fifo_wr_GEN_1: if ENG_NUM = 1 generate
        out_fifo_wrdata <= scale_user_out(0) & or_reduce(scale_last_out) & scale_dvalid_out(0) & scale_data_out(0);
    end generate;
    out_fifo_wr_GEN_2: if ENG_NUM = 2 generate
        out_fifo_wrdata <= scale_user_out(0) & or_reduce(scale_last_out) & scale_dvalid_out & scale_data_out(1) & scale_data_out(0);
    end generate;

    u_out_fifo: entity utils.fifo_fwft
    generic map(
        DWIDTH        => ENG_NUM*8*3+ENG_NUM+1+1,
        DEPTH         => 32,
        WR_AFULL_WM   => 24
    )
    port map(
        clk       => clk,
        rst       => rst,
        wr_en     => out_fifo_wren,
        wr_data   => out_fifo_wrdata,
        wr_afull  => out_fifo_afull,
        wr_full   => open,
        rd_en     => m_axis_tready_m_i,
        rd_data   => out_fifo_rddata,
        rd_valid  => out_fifo_valid  
    );

    m_axis_tvalid_m_o <= out_fifo_valid; 
    m_axis_tdata_m_o  <= out_fifo_rddata(ENG_NUM*8*3-1 downto 0); --scale_data_out;
    gen_strobe: for i in 0 to ENG_NUM-1 generate
        m_axis_tstrobe_m_o(i*3+0) <= out_fifo_rddata(ENG_NUM*8*3+i);
        m_axis_tstrobe_m_o(i*3+1) <= out_fifo_rddata(ENG_NUM*8*3+i);
        m_axis_tstrobe_m_o(i*3+2) <= out_fifo_rddata(ENG_NUM*8*3+i);
    end generate;
    m_axis_tlast_m_o  <= out_fifo_rddata(ENG_NUM*8*3+ENG_NUM);
    m_axis_tuser_m_o(0) <= out_fifo_rddata(ENG_NUM*8*3+ENG_NUM+1);
    
end architecture rtl;

