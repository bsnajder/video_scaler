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
-- File: scale_fsm_hor.vhd
-- Description: Horizontal scaling finite state machine for video scaler IP.
--              Implements horizontal interpolation with configurable scaling 
--              ratios, edge mirroring, and AXI4-Stream interface for RGB video.
-- Author: Boris Snajder
-- Created: 2025
-- Modified: 2025-09-20
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.std_logic_misc.ALL;

library utils;
use utils.utils_pkg.all;

library scale_ip;
use scale_ip.scale_pkg.all;

entity scale_fsm_hor is
    port ( 
	    clk         : in std_logic;
	    rst         : in std_logic;
        --
        hor_scale     : in std_logic_vector(31 downto 0);
    	--
    	axis_tvalid   : in std_logic;
    	axis_tready   : out std_logic;
    	axis_tdata    : in std_logic_vector(ENG_NUM*3*8-1 downto 0);
    	axis_tlast    : in std_logic;
        axis_tstrobe  : in std_logic_vector(ENG_NUM*3-1 downto 0);
    	axis_tuser    : in std_logic_vector(0 downto 0);
	    --
        m_axis_tdata  : out std_logic_vector(ENG_NUM*3*8-1 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in std_logic;
        m_axis_tlast  : out std_logic;
        m_axis_tstrobe: out std_logic_vector(ENG_NUM*3-1 downto 0);
        m_axis_tuser  : out std_logic_vector(0 downto 0)
    );
end scale_fsm_hor;

--architecture declaration
architecture rtl of scale_fsm_hor is

    type scale_fsm_t is (
        IDLE_s, 
        RUN_s, 
        FLUSH_s,
        LAST_s
    );

    signal scale_fsm_cs     : scale_fsm_t;
    signal scale_fsm_ns     : scale_fsm_t;

    signal axis_tready_int  : std_logic := '1';
    signal axis_data_valid  : std_logic;

    signal tap_data         : tap_arr_t;
    signal tap_ptr          : tap_ptr_comp_t;

    signal tap_valid        : std_logic_vector(0 to TAP_REG_NUM-1) := (others => '0');
    signal tap_last         : std_logic_vector(0 to TAP_REG_NUM-1) := (others => '0');
    signal tap_user         : std_logic_vector(0 to TAP_REG_NUM-1) := (others => '0');

    signal eng_data         : eng_data_t; --data for the scaling engines
    type eng_data_vec_t     is array (0 to ENG_NUM-1) of std_logic_vector(3*8*TAP_NUM-1 downto 0);
    signal eng_data_vec     : eng_data_vec_t;

    signal scale_cnt        : scale_cnt_t; --counter for scaling
    signal scale_cnt_phase  : scale_cnt_t; --counter for scaling
    signal scale_cnt_del    : scale_cnt_t := (others => (others => '0')); --counter for scaling
    signal scale_cnt_inc    : unsigned(SCALE_CNT_SIZE-1 downto 0) := to_unsigned(1398101, SCALE_CNT_SIZE); --1398101 is upscale 3 (1:3)
    signal scale_run        : std_logic_vector(0 to ENG_NUM-1) := (others => '0');
    signal scale_run_last   : std_logic_vector(0 to ENG_NUM-1) := (others => '0');
    signal scale_run_user   : std_logic_vector(0 to ENG_NUM-1) := (others => '0');
    signal scale_stall      : std_logic; --if we need to stall input, so scaling engines can do their jobs (upscale)
    type scale_run_ptr_t    is array (0 to ENG_NUM-1) of unsigned(0 downto 0);
    signal scale_run_ptr    : scale_run_ptr_t; --this is good only for up to 2 scaling engines
    signal scale_run_ptr_phase  : scale_run_ptr_t; --this is good only for up to 2 scaling engines

    signal scale_data_out       : std_logic_vector(ENG_NUM*8*3-1 downto 0);
    signal scale_data_out_val   : std_logic_vector(ENG_NUM-1 downto 0);
    signal scale_data_out_last  : std_logic_vector(ENG_NUM-1 downto 0);
    signal scale_data_out_user  : std_logic_vector(ENG_NUM-1 downto 0);

    signal out_fifo_wrdata      : std_logic_vector(ENG_NUM*3*8+1+ENG_NUM+1-1 downto 0);
    signal out_fifo_wren        : std_logic;
    signal out_fifo_rddata      : std_logic_vector(ENG_NUM*3*8+1+ENG_NUM+1-1 downto 0);
    signal out_fifo_empty       : std_logic;
    signal out_fifo_afull       : std_logic;
    signal out_fifo_valid       : std_logic;

    type fifo_data_shift_t is record
        data    : std_logic_vector(3*8-1 downto 0);
        valid   : std_logic;
        last    : std_logic;
        user    : std_logic;
    end record;
    constant FIFO_DATA_SHIFT_INIT : fifo_data_shift_t := (data => (others => '0'), valid => '0', last => '0', user => '0');

    type   fifo_data_shift_arr_t is array (3 downto 0) of fifo_data_shift_t;

    signal out_fifo_shift           : fifo_data_shift_arr_t;

    signal out_fifo_wrdata_shift : std_logic_vector(2*ENG_NUM*8-1 downto 0);
    signal out_fifo_wrdata_shift_valid : std_logic_vector(2*ENG_NUM-1 downto 0);
    signal out_fifo_wrdata_shift_last  : std_logic_vector(2*ENG_NUM-1 downto 0);
    signal out_fifo_wrdata_shift_user  : std_logic_vector(2*ENG_NUM-1 downto 0);
begin

    scale_cnt_inc <= resize(unsigned(hor_scale), scale_cnt_inc'length);


    axis_tready_int <= '1' when (scale_fsm_cs = RUN_s and scale_stall = '0' and out_fifo_afull = '0') else '0';
    axis_tready <= axis_tready_int;

    axis_data_valid <= '1' when (axis_tvalid = '1' and axis_tready_int = '1' and scale_fsm_cs = RUN_s) else '0';

	process(clk)
	begin
		if rising_edge(clk) then
            if rst = '1' then
                scale_fsm_cs <= IDLE_s;
            else
                scale_fsm_cs <= scale_fsm_ns;
            end if;
		end if;
	end process;


    process (scale_fsm_cs, axis_tvalid, axis_tready_int, axis_data_valid, axis_tlast, tap_last, scale_stall, out_fifo_afull, out_fifo_wren, out_fifo_wrdata)
    begin
        case scale_fsm_cs is
            when IDLE_s =>
                if axis_tvalid = '1' then
                    scale_fsm_ns <= RUN_s;
                else
                    scale_fsm_ns <= IDLE_s;
                end if;

            when RUN_s =>
                if axis_tlast = '1' and axis_data_valid = '1' then
                    scale_fsm_ns <= FLUSH_s;
                else
                    scale_fsm_ns <= RUN_s;
                end if;

            when FLUSH_s =>
                if tap_last(TAP_NUM/2 to TAP_NUM/2+(ENG_NUM-1)) /= std_logic_vector(to_unsigned(0, ENG_NUM)) and scale_stall = '0' then --check if any of central taps is the last pixel
                    scale_fsm_ns <= LAST_s;
                else
                    scale_fsm_ns <= FLUSH_s;
                end if;

            when LAST_s =>
                if out_fifo_wren = '1' and out_fifo_wrdata(out_fifo_wrdata'left-1) = '1' then
                    scale_fsm_ns <= IDLE_s;
                else
                    scale_fsm_ns <= LAST_s;
                end if;

            when others =>
                scale_fsm_ns <= IDLE_s;
        end case;
    end process;

    p_ptr_shift: process(clk)
        variable tap_last_found : std_logic;
        variable last_idx : integer;
        variable tap_last_v : tap_ptr_comp_t;
        variable shift_num_calc : natural;
        
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tap_ptr <= (others => (others => '0'));
            else
                if scale_fsm_cs = IDLE_s then
                    tap_ptr <= get_tap_init_ptr;
                elsif scale_fsm_cs = RUN_s then 
                    if axis_data_valid = '1' then --this is applicable to RUN_s state
                        tap_ptr(0 to TAP_REG_NUM-1-(ENG_NUM)) <= tap_ptr(ENG_NUM to TAP_REG_NUM-1);
                        if axis_tlast = '0' then
                            tap_ptr(TAP_REG_NUM-1-(ENG_NUM-1) to TAP_REG_NUM-1) <= (others => to_signed(0, tap_ptr(0)'length));
                        else
                            tap_last_found := '0';
                            last_idx := 0;

                            if (ENG_NUM > 1) then
                                for tap_idx in 0 to ENG_NUM-2 loop --tap_idx is pointer to taps
                                   
                                        if axis_tstrobe(3*tap_idx+1) = '0' then --if next byte is not valid, we are the last
                                            if tap_last_found = '0' then
                                                last_idx := tap_idx;
                                            end if;
                                            tap_last_found := '1';
                                        end if;
                                    
                                end loop;
                            end if;

                            tap_last_v := get_tap_last_ptr;
                            tap_last_v(0 to TAP_REG_NUM-1) := tap_ptr(0 to TAP_REG_NUM-1);

                            --if tap_last_found is 0, last byte is last, and we do not need to shift anything
                            if tap_last_found = '1' then
                            --if tap_last_found is 1, that means that we need to shift mirroring pointer of the end  
                                if ENG_NUM > 1 then --if ENG_NUM = 1 than we do not need to shift anything
                                    --last_idx can go from 0 to ENG_NUM-2; if it is ENG_NUM-2 we need to shift by 1, if it is ENG_NUM-3 we need to shift by 2, etc.
                                    shift_num_calc := ENG_NUM - 1 - last_idx;
                                    for i in 0 to ENG_NUM-2 loop

                                        if i = shift_num_calc then
                                            tap_last_v(0 to TAP_REG_NUM+TAP_NUM/2-1-i) := tap_last_v(i to TAP_REG_NUM+TAP_NUM/2-1);
                                        end if;
                                    end loop;
                                end if;
                            end if;

                            tap_ptr <= tap_last_v;

                        end if;
                    end if;
                elsif scale_fsm_cs = FLUSH_s then
                    if scale_stall = '0' and out_fifo_afull = '0' then
                        tap_ptr(0 to TAP_REG_NUM+TAP_NUM/2-1-(ENG_NUM)) <= tap_ptr(ENG_NUM to TAP_REG_NUM+TAP_NUM/2-1);
                    end if;
                end if;
            end if;
        end if;
    end process;

    p_data_in_shift: process(clk)
        variable last_found : std_logic;
        variable pix_pos : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tap_data <= (others => (others => x"00"));
                tap_valid <= (others => '0');
                tap_last <= (others => '0');
                tap_user <= (others => '0');

            else
                if scale_fsm_cs = IDLE_s then
                    tap_data <= (others => (others => x"00"));
                    tap_valid <= (others => '0');
                    tap_last <= (others => '0');
                    tap_user <= (others => '0');

                elsif scale_fsm_cs = RUN_s then  
                    if axis_data_valid = '1' then --this is applicable to RUN_s state

                        for tap_idx in 0 to TAP_REG_NUM-ENG_NUM-1 loop --tap_idx is pointer to taps
                            --tap_data'length = 3 (0 to 2)
                            for pix_el_idx in 0 to 2 loop --pixel_el_idx is pointer to R,G,B parts of pixel
                                tap_data(pix_el_idx)(tap_idx) <= tap_data(pix_el_idx)(tap_idx + ENG_NUM);
                            end loop;
                            tap_valid(tap_idx) <= tap_valid(tap_idx + ENG_NUM);
                            tap_last(tap_idx) <= tap_last(tap_idx + ENG_NUM);
                            tap_user(tap_idx) <= tap_user(tap_idx + ENG_NUM);
                        end loop;

                        last_found := '0';
                        for tap_idx in TAP_REG_NUM-ENG_NUM to TAP_REG_NUM-1 loop --tap_idx is pointer to taps
                            pix_pos := tap_idx - (TAP_REG_NUM-ENG_NUM);
                            --tap_data'length = 3 (0 to 2)
                            for pix_el_idx in 0 to 2 loop --pixel_el_idx is pointer to R,G,B parts of pixel
                                --tap_data(pix_el_idx)(tap_idx) <= axis_tdata((tap_idx+1 - (TAP_REG_NUM-ENG_NUM))*8-1 downto (tap_idx - (TAP_REG_NUM-ENG_NUM))*8); --we are still missing indexing for RGB parts in axis_tdata
                                tap_data(pix_el_idx)(tap_idx) <= axis_tdata((pix_pos*3+pix_el_idx+1)*8-1 downto (pix_pos*3+pix_el_idx)*8); --we are still missing indexing for RGB parts in axis_tdata
                            end loop;
                            if tap_idx = TAP_REG_NUM - ENG_NUM then
                                tap_user(tap_idx) <= axis_tuser(0);
                            else
                                tap_user(tap_idx) <= '0';
                            end if;

                            tap_valid(tap_idx) <= axis_tstrobe(3*pix_pos); --TODO we need to extract this info trom tvalid and tstrobe signals
                            if tap_idx < TAP_REG_NUM-1 then
                                if axis_tstrobe(3*pix_pos+1) = '1' then --if next byte is valid, we are not last pixel
                                    tap_last(tap_idx) <= '0';
                                else
                                    if last_found = '0' then
                                        tap_last(tap_idx) <= axis_tlast;
                                    end if;
                                    last_found := '1';
                                end if;
                            else
                                if last_found = '0' then
                                    tap_last(tap_idx) <= axis_tlast;
                                end if;
                            end if;
                        end loop;

                    end if;

                elsif scale_fsm_cs = FLUSH_s then

                    if scale_stall = '0' and out_fifo_afull = '0' then

                            for tap_idx in 0 to TAP_REG_NUM-ENG_NUM-1 loop --tap_idx is pointer to taps
                                --tap_data'length = 3 (0 to 2)
                                for pix_el_idx in 0 to 2 loop --pixel_el_idx is pointer to R,G,B parts of pixel
                                    tap_data(pix_el_idx)(tap_idx) <= tap_data(pix_el_idx)(tap_idx + ENG_NUM);
                                end loop;
                                tap_valid(tap_idx) <= tap_valid(tap_idx + ENG_NUM);
                                tap_last(tap_idx) <= tap_last(tap_idx + ENG_NUM);
                                tap_user(tap_idx) <= tap_user(tap_idx + ENG_NUM);
                            end loop;

                            for tap_idx in TAP_REG_NUM-ENG_NUM to TAP_REG_NUM-1 loop --tap_idx is pointer to taps
                                --tap_data'length = 3 (0 to 2)    
                                for pix_el_idx in 0 to 2 loop --pixel_el_idx is pointer to R,G,B parts of pixel
                                    tap_data(pix_el_idx)(tap_idx) <= x"00";
                                end loop;
                                tap_valid(tap_idx) <= '0';
                                tap_last(tap_idx) <= '0';
                                tap_user(tap_idx) <= '0';
                            end loop;
                    end if;
                end if;
                
            end if;
        end if;
    end process p_data_in_shift;    

    --assemble data for scale engine
    eng_data_gen: for i in 0 to ENG_NUM-1 generate

        process (tap_data, tap_ptr, scale_run_ptr_phase)
            variable addr_fetch : integer;
        begin
            
            for tap_i in 0 to TAP_NUM-1+(ENG_NUM-1) loop
                if scale_run_ptr_phase(i) = to_unsigned(0, scale_run_ptr_phase(i)'length) then
                    addr_fetch := tap_i + 1;
                    addr_fetch := addr_fetch + to_integer(signed(RESOLVE(std_logic_vector(tap_ptr(tap_i+1)))));
                else
                    addr_fetch := tap_i + 2;
                    addr_fetch := addr_fetch + to_integer(signed(RESOLVE(std_logic_vector(tap_ptr(tap_i+2)))));
                end if;

                 if (addr_fetch > TAP_REG_NUM-1) then
                        addr_fetch := TAP_REG_NUM - 1;
                 elsif (addr_fetch < 0) then
                        addr_fetch := 0;
                 end if;
                 --tap_data'length = 3 (0 to 2)
                 for eng_idx in 0 to 2 loop
                     eng_data(i)(eng_idx)(tap_i) <= tap_data(eng_idx)(addr_fetch);
                 end loop;
            end loop;

        end process;
    
    end generate;

   p_scale_cnt: process(clk)
       variable scale_cnt_next_v    : scale_cnt_t;
       variable scaler_run_v        : std_logic_vector(0 to ENG_NUM-1); 
       variable scaler_stall_v      : std_logic_vector(0 to ENG_NUM-1);
       variable scale_run_ptr_v     : scale_run_ptr_t;
       variable no_data             : std_logic;
   begin
    if rising_edge(clk) then
        if rst = '1' then
           scale_cnt            <= (others => (others => '0')); 
           scale_cnt_phase      <= (others => (others => '0')); 
           scale_cnt_del        <= (others => (others => '0')); 
           scale_run            <= (others => '0');
           scale_stall          <= '0';
           scale_run_ptr        <= (others => (others => '0'));
           scale_run_ptr_phase  <= (others => (others => '0'));
        else
            if scale_fsm_cs = IDLE_s then
                scale_cnt           <= (others => (others => '0'));
                scale_cnt_phase     <= (others => (others => '0')); 
                scale_cnt_del       <= (others => (others => '0')); 
                scale_run           <= (others => '0');
                scale_stall         <= '0';
                scale_run_ptr       <= (others => (others => '0'));
                scale_run_ptr_phase <= (others => (others => '0'));

            elsif scale_fsm_cs = RUN_s  or scale_fsm_cs = FLUSH_s then

                --we shall advancing our phase counter when we have available data for processing, or when we are still procesing old data (indicated by scale_stall = '1')
                if ((tap_valid(TAP_NUM/2+ENG_NUM) = '1' and ( (scale_fsm_cs = RUN_s and axis_data_valid = '1') or scale_fsm_cs = FLUSH_s) ) 
                    or scale_stall = '1') and out_fifo_afull = '0' then

                    if ENG_NUM = 1 then
                       calc_next_phase(scale_cnt(ENG_NUM-1), scale_cnt_inc, scale_cnt_next_v(0), scaler_run_v(0), scaler_stall_v(0));
                       scale_run(0) <= scaler_run_v(0);
                       scale_stall <= scaler_stall_v(0);

                   elsif ENG_NUM = 2 then
                       calc_next_phase(scale_cnt(ENG_NUM-1), scale_cnt_inc, scale_cnt_next_v(0), scaler_run_v(0), scaler_stall_v(0));
                       scale_run(0) <= scaler_run_v(0);
                       scale_run_ptr_v(0) := scale_run_ptr(0); --ENG_NUM-1);

                       if scaler_run_v(0) = '1'  and scaler_stall_v(0) = '1' then
                            scale_run_ptr_v(1) := scale_run_ptr_v(0);
                       else -- if we do not run scaler, that means that we need new data (that is we need to increase pointer)
                            scale_run_ptr_v(1) := scale_run_ptr_v(0) + 1;
                       end if;

                       no_data := '0';
                       if scale_run_ptr_v(1) = to_unsigned(0, scale_run_ptr_v(1)'length) and scale_run_ptr_v(0) = to_unsigned(1, scale_run_ptr_v(1)'length) then
                           scale_cnt_next_v(1) := scale_cnt_next_v(0);
                           scaler_run_v(1) := '0';
                           scaler_stall_v(1) := '0';
                           no_data := '1';
                           scale_run_ptr_v(0) := scale_run_ptr_v(1);
                       else
                           calc_next_phase(scale_cnt_next_v(0), scale_cnt_inc, scale_cnt_next_v(1), scaler_run_v(1), scaler_stall_v(1));
                           if scaler_run_v(1) = '1' and scaler_stall_v(1) = '1' then
                                scale_run_ptr_v(0) := scale_run_ptr_v(1);
                            else
                                scale_run_ptr_v(0) := scale_run_ptr_v(1) + 1;
                            end if;
                       end if;
                        
                       scale_run(ENG_NUM-1) <= scaler_run_v(ENG_NUM-1);

                        if (((scaler_run_v(1) = '1' and scaler_stall_v(1) = '0') or (scaler_run_v(1) = '0')) and scale_run_ptr_v(1) = to_unsigned(1, scale_run_ptr_v(1)'length)) or 
                         (no_data = '1') then
                            scale_stall <= '0';
                        else
                            scale_stall <= '1';
                        end if;

                        scale_run_ptr(ENG_NUM-1) <= scale_run_ptr_v(ENG_NUM-1);
                        scale_run_ptr <= scale_run_ptr_v;
                        scale_run_ptr_phase(0) <= scale_run_ptr(0);
                        scale_run_ptr_phase(ENG_NUM-1) <= scale_run_ptr_v(ENG_NUM-1);
                    end if;
                
                    scale_cnt <= scale_cnt_next_v;
                    if ENG_NUM = 2 then
                        scale_cnt_phase(ENG_NUM-1) <= scale_cnt_next_v(0);
                        scale_cnt_phase(0) <= scale_cnt(ENG_NUM-1); 
                    else
                        scale_cnt_phase(0) <= scale_cnt(0);
                    end if;
                else
                    scale_run <= (others => '0');
                end if;

                scale_cnt_del <= scale_cnt_phase;

            end if;
        end if;
    end if;
   end process p_scale_cnt;

   -- Instantiate scale_eng
    u_scale_eng_gen: for j in 0 to ENG_NUM-1 generate
        data_vec_gen: for dat_idx in 0 to TAP_NUM-1 generate
            col_comp_gen: for col_idx in 0 to 2 generate
                eng_data_vec(j)((col_idx*TAP_NUM + dat_idx+1)*8-1 downto (col_idx*TAP_NUM + dat_idx)*8) <= eng_data(j)(col_idx)(dat_idx); -- when scale_run_ptr(j) = to_unsigned(0, scale_run_ptr(j)'length) else eng_data(0)(j)(dat_idx+1);
            end generate;
        end generate;

        scale_run_last(j) <= scale_run(j) when (scale_fsm_cs = FLUSH_s and scale_fsm_ns /= FLUSH_s) else '0';
        scale_run_user(j) <= tap_user(TAP_NUM/2+j);

         u_scale_eng: entity scale_ip.scale_eng
         port map
         (
              clk           => clk,
              rst           => rst,
              --
              data_in       => eng_data_vec(j),
              data_in_val   => scale_run(j),
              data_in_last  => scale_run_last(j), 
              data_in_user  => scale_run_user(j),
              phase_in      => std_logic_vector(scale_cnt_phase(j)(SCALE_CNT_FRAC_SIZE-1 downto SCALE_CNT_FRAC_SIZE-1-log2(PHASE_NUM)+1)),
              --
              data_out      => scale_data_out((j+1)*8*3-1 downto j*8*3),
              data_out_val  => scale_data_out_val(j),
              data_out_user => scale_data_out_user(j),
              data_out_last => scale_data_out_last(j)
         );
    end generate;

    gen_out_data_1ENG: if ENG_NUM = 1 generate
        out_fifo_wrdata <= scale_data_out_user & or_reduce(scale_data_out_last) & scale_data_out_val & scale_data_out;
        out_fifo_wren <= scale_data_out_val(0);
    end generate;

    gen_out_data_2ENG: if ENG_NUM = 2 generate

        p_out_data_shift_handle: process(clk)
            variable write_word_helper       : std_logic_vector(ENG_NUM*3*8-1 downto 0);
            variable write_word_valid_helper : std_logic_vector(ENG_NUM-1 downto 0);
            variable write_word_last_helper  : std_logic;
            variable write_word_user_helper  : std_logic;
        begin
            if rising_edge(clk) then
                if rst = '1' then
                    out_fifo_wrdata_shift <= (others => '0');
                    out_fifo_wrdata_shift_valid <= (others => '0');
                    out_fifo_wrdata_shift_last  <= (others => '0');
                    out_fifo_wrdata_shift_user  <= (others => '0');

                    out_fifo_shift <= (others => FIFO_DATA_SHIFT_INIT);

                else
                    if ENG_NUM = 2 then
                        write_word_valid_helper := (others => '0');
                        write_word_last_helper  := or_reduce(scale_data_out_last);
                        write_word_user_helper  := or_reduce(scale_data_out_user);
                        if scale_data_out_val = "11" then
                            write_word_valid_helper := (others => '1');
                            write_word_helper := scale_data_out(3*8*2-1 downto 0);

                        elsif scale_data_out_val = "01" then
                            write_word_valid_helper := (0 => '1', others => '0');
                            write_word_helper := X"000000" & scale_data_out(3*8-1 downto 0);

                        elsif scale_data_out_val = "10" then
                            write_word_valid_helper := (0 => '1', others => '0');
                            write_word_helper := X"000000" & scale_data_out(3*8*2-1 downto 3*8);
                        
                        end if;

                        if out_fifo_shift(3).valid = '1' and out_fifo_shift(2).valid = '1' then
                            out_fifo_shift(0) <= out_fifo_shift(2);
                            out_fifo_shift(1) <= out_fifo_shift(3);

                            out_fifo_shift(2).last <= write_word_last_helper;
                            out_fifo_shift(2).user <= write_word_user_helper;
                            out_fifo_shift(3).last <= '0';
                            out_fifo_shift(3).user <= '0';
                            for i in 0 to 1 loop
                                out_fifo_shift(i+2).valid <= write_word_valid_helper(i);
                                out_fifo_shift(i+2).data <= write_word_helper((i+1)*8*3-1 downto i*8*3);
                            end loop;       

                        elsif out_fifo_shift(3).valid = '0' and out_fifo_shift(2).valid = '1' then
                            if scale_data_out_val /= "00" or (out_fifo_shift(3).last = '1' or out_fifo_shift(2).last = '1') then --we have new data or we have (last) data waiting to be flushed
                                out_fifo_shift(0) <= out_fifo_shift(2);

                                out_fifo_shift(1).data <= write_word_helper(3*8-1 downto 0);
                                out_fifo_shift(1).valid <= write_word_valid_helper(0);

                                out_fifo_shift(2).data <= write_word_helper(3*8*2-1 downto 3*8);
                                out_fifo_shift(2).valid <= write_word_valid_helper(1);
                                
                                out_fifo_shift(3).data <= (others => '0');
                                out_fifo_shift(3).valid <= '0';

                                if scale_data_out_val = "11" then
                                    out_fifo_shift(1).last <= '0';
                                    out_fifo_shift(2).last <= write_word_last_helper;
                                    out_fifo_shift(3).last <= '0';
                                else
                                    out_fifo_shift(1).last <= write_word_last_helper;
                                    out_fifo_shift(2).last <= '0';
                                    out_fifo_shift(3).last <= '0';

                                end if;

                            else
                                out_fifo_shift(1).valid <= '0';
                                out_fifo_shift(0).valid <= '0';
                            end if;
                        elsif out_fifo_shift(3).valid = '0' and out_fifo_shift(2).valid = '0' then
                            if scale_data_out_val = "11" then
                                out_fifo_shift(0).data <= write_word_helper(3*8-1 downto 0);
                                out_fifo_shift(0).valid <= write_word_valid_helper(0);
                                out_fifo_shift(0).last <= write_word_last_helper;
                                out_fifo_shift(0).user <= write_word_user_helper;

                                out_fifo_shift(1).data <= write_word_helper(2*3*8-1 downto 3*8);
                                out_fifo_shift(1).valid <= write_word_valid_helper(1);
                                out_fifo_shift(1).last <= '0';
                                out_fifo_shift(1).user <= '0';

                                out_fifo_shift(2) <= FIFO_DATA_SHIFT_INIT;
                                out_fifo_shift(3) <= FIFO_DATA_SHIFT_INIT;
                            else
                                out_fifo_shift(0) <= FIFO_DATA_SHIFT_INIT;
                                out_fifo_shift(1) <= FIFO_DATA_SHIFT_INIT;

                                out_fifo_shift(2).data <= write_word_helper(3*8-1 downto 0);
                                out_fifo_shift(2).valid <= write_word_valid_helper(0);
                                out_fifo_shift(2).last <= write_word_last_helper;
                                out_fifo_shift(2).user <= write_word_user_helper;


                                out_fifo_shift(3).data <= write_word_helper(2*3*8-1 downto 3*8);
                                out_fifo_shift(3).valid <= write_word_valid_helper(1);
                                out_fifo_shift(3).last <= '0';
                                out_fifo_shift(3).user <= '0';
                            end if;

                        end if;
                    end if;
                end if;
            end if;

        end process p_out_data_shift_handle;

        out_fifo_wren <= or_reduce(out_fifo_shift(1).valid & out_fifo_shift(0).valid);
        out_fifo_wrdata <= out_fifo_shift(0).user & or_reduce(out_fifo_shift(1).last & out_fifo_shift(0).last) & out_fifo_shift(1).valid & out_fifo_shift(0).valid & out_fifo_shift(1).data & out_fifo_shift(0).data;

    end generate;

    u_out_fifo: entity utils.fifo_fwft
    generic map(
        DWIDTH        => ENG_NUM*3*8+ENG_NUM+1+1,
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
        rd_en     => m_axis_tready,
        rd_data   => out_fifo_rddata,
        rd_valid  => out_fifo_valid  
    );    

    m_axis_tvalid <= out_fifo_valid; 
    m_axis_tdata  <= out_fifo_rddata(ENG_NUM*3*8-1 downto 0); --scale_data_out;
    gen_strobe: for i in 0 to ENG_NUM-1 generate
        m_axis_tstrobe(i*3+0) <= out_fifo_rddata(ENG_NUM*3*8+i);
        m_axis_tstrobe(i*3+1) <= out_fifo_rddata(ENG_NUM*3*8+i);
        m_axis_tstrobe(i*3+2) <= out_fifo_rddata(ENG_NUM*3*8+i);
    end generate;
    m_axis_tlast  <= out_fifo_rddata(ENG_NUM*3*8+ENG_NUM);
    m_axis_tuser(0) <= out_fifo_rddata(ENG_NUM*3*8+ENG_NUM+1);

end rtl;
