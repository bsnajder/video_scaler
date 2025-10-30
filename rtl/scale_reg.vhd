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
-- File: scale_reg.vhd
-- Description: AXI4-Lite register interface for video scaler IP configuration.
--              Provides runtime control of horizontal/vertical scaling ratios,
--              input resolution settings, and status monitoring.
-- Author: Boris Snajder
-- Created: 2025
-- Modified: 2025-09-20
-------------------------------------------------------------------------------

-- Library declaration
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library utils;
use utils.utils_pkg.all;

library scale_ip;
use scale_ip.scale_pkg.all;

entity scale_reg is
    generic (
        AXI_AWIDTH      : positive := 32;
        AXI_DWIDTH      : positive := 32
    );    
    port (
        aclk                    :   in std_logic;
        aresetn                 :   in std_logic;
        --      	            
        awvalid                 :   in std_logic;
        awready                 :   out std_logic;
        awaddr                  :   in std_logic_vector(AXI_AWIDTH-1 downto 0);
        awprot                  :   in std_logic_vector(2 downto 0);
        --      	            
        wvalid                  :   in std_logic;
        wready                  :   out std_logic;
        wdata                   :   in std_logic_vector(AXI_DWIDTH-1 downto 0);
        wstrb                   :   in std_logic_vector(AXI_DWIDTH/8-1 downto 0);
        --      	            
        bvalid                  :   out std_logic;
        bready                  :   in std_logic;
        bresp                   :   out std_logic_vector(1 downto 0);
        --      	            
        arvalid                 :   in std_logic;
        arready                 :   out std_logic;
        araddr                  :   in std_logic_vector(AXI_AWIDTH-1 downto 0);
        arprot                  :   in std_logic_vector(2 downto 0);    
        --      	            
        rvalid                  :   out std_logic;
        rready                  :   in std_logic;
        rdata                   :   out std_logic_vector(AXI_DWIDTH-1 downto 0);
        rresp                   :   out std_logic_vector(1 downto 0);
        -- IRQ
        irq                     :   out std_logic;
        --
        scale_hor               :   out std_logic_vector(31 downto 0);
        scale_ver               :   out std_logic_vector(31 downto 0);
        res_ver                 :   out std_logic_vector(15 downto 0)
    );
end entity scale_reg;

architecture rtl of scale_reg is

    constant REG_ARR_SIZE           : integer := 7;
    subtype  REG_ARR_DEC_RANGE      is natural range LOG2(REG_ARR_SIZE)+2-1 downto 2;
    
    type  reg_des_def is record
        register_name   : string(1 to 16);
        register_index  : integer;
        register_ro     : boolean;
    end record;

    type reg_des_arr_t                is array (natural range <>) of reg_des_def;
    constant reg_description: reg_des_arr_t(0 to REG_ARR_SIZE-1) := 
    (
         0  => ("REG_SC_INFO     ",  0, true), --0
         1  => ("REG_SC_CONF     ",  1, false), --4
         2  => ("REG_SC_HCOEF    ",  2, false), --8
         3  => ("REG_SC_VCOEF    ",  3, false), --C
         4  => ("REG_SC_VRES     ",  4, false), --10
         5  => ("REG_IRQ_MASK    ",  5, false), --14
         6  => ("REG_IRQ_FLAG    ",  6, false)  --18
    );

        
    -- Signal declarations
    signal areset                   : std_logic;
    type reg_arr_t                 is array(REG_ARR_SIZE-1 downto 0) of unsigned(31 downto 0);
    signal reg_arr                 : reg_arr_t := (others => (others => '0'));
    
    signal reg_wsel                : unsigned(REG_ARR_SIZE-1 downto 0) := (others => '0');
    signal reg_rsel                : unsigned(REG_ARR_SIZE-1 downto 0) := (others => '0');
    
    signal decode_waddr            : unsigned(REG_ARR_DEC_RANGE);
    signal decode_raddr            : unsigned(REG_ARR_DEC_RANGE);

    signal awready_i                : std_logic := '1';
    signal wr_op_active             : std_logic := '0';
    
    signal wready_i                 : std_logic := '0';
    signal bvalid_i                 : std_logic := '0';
    signal arready_i                : std_logic := '0';
    signal rvalid_i                 : std_logic := '0';

    signal wstrb_h                  : unsigned(AXI_DWIDTH/8-1 downto 0);
    signal wdata_h                  : unsigned(AXI_DWIDTH-1 downto 0); 
    
    signal arready_d                : std_logic := '0';
    signal arvalid_d                : std_logic := '0';    

    signal read_busy                : std_logic;    

    signal irq_flags                : std_logic_vector(0 downto 0);

    type t_wr_fsm is 
        (
            WR_READY_s,
            WR_RUN_s
        );
    signal wr_fsm_cs : t_wr_fsm;
    signal wr_fsm_ns : t_wr_fsm;

    function get_reg_data(reg_arr_in: in reg_arr_t; reg_name: string) return unsigned is
        variable tmp_data   : unsigned(AXI_DWIDTH-1 downto 0);
    begin
        tmp_data := X"BEADC00D";
        for i in reg_description'low to reg_description'high loop
            if reg_description(i).register_name(reg_name'range) = reg_name then
                tmp_data := reg_arr_in(i);
                return tmp_data;
            end if;
        end loop;
        return tmp_data;
    end get_reg_data;
    
    function get_reg_index(reg_name: string) return integer is
        variable tmp_data   : integer;
    begin
        tmp_data := -1;
        for i in reg_description'low to reg_description'high loop
            if reg_description(i).register_name(reg_name'range) = reg_name then
                tmp_data := i;
                return tmp_data;
            end if;
        end loop;
        return tmp_data;
    end get_reg_index;    
    
    function update_reg ( reg_in    : in unsigned(AXI_DWIDTH-1 downto 0); 
                          data_in   : in unsigned(AXI_DWIDTH-1 downto 0); 
                          strobe_in : in unsigned(AXI_DWIDTH/8-1 downto 0)
                        ) 
        return unsigned is
        variable temp_reg : unsigned(data_in'length-1 downto 0);    
    begin
        temp_reg(reg_in'range) := reg_in;
        for i in (AXI_DWIDTH/8-1) downto 0 loop
            if (strobe_in(i) = '1') then
                temp_reg((i+1)*8-1 downto i*8) := data_in((i+1)*8-1 downto i*8);
            end if;
        end loop;
        return temp_reg;
    end;        

begin

    areset <= not aresetn;
    
    awready     <= awready_i;
    wready      <= wready_i;
    bvalid      <= bvalid_i;
    arready     <= arready_i;
    rvalid      <= rvalid_i;
    bresp       <= (others => '0');
    rresp       <= (others => '0');    
    
    -----------------------------------------
    --write channel
    -----------------------------------------
    process (aclk)
    begin
        if rising_edge(aclk) then
            if areset = '1' then
                wr_fsm_cs <= WR_READY_s;
            else
                wr_fsm_cs <= wr_fsm_ns;
            end if;
        end if;
    end process;

    process (wr_fsm_cs, awvalid, wvalid, bready, bvalid_i)
    begin
        case (wr_fsm_cs) is
            when WR_READY_s =>
                if (awvalid = '1') then --this assumes that awready_i = '1'
                    wr_fsm_ns <= WR_RUN_s;
                else
                    wr_fsm_ns <= WR_READY_s;
                end if;
            when WR_RUN_s =>
                if (bready = '1' and bvalid_i = '1') then
                    wr_fsm_ns <= WR_READY_s;
                else
                    wr_fsm_ns <= WR_RUN_s;
                end if;
            when others =>
                wr_fsm_ns <= WR_READY_s;
        end case;
    end process;

    awready_i <= '1' when wr_fsm_cs = WR_READY_s else '0';
    
    process (aclk)
    begin
        if rising_edge(aclk) then
            if areset = '1' then
                wr_op_active <= '0';
                reg_wsel <= (others => '0');
            else
                --we do not pipeline the write operation
                --we have two options, wvalid is asserted when awvalid is asserted, or wvalid will get asserted at later stage
                reg_wsel <= (others => '0');
                if wr_fsm_cs = WR_READY_s and wr_fsm_ns = WR_RUN_s then --address is goind to be acked
                    if (wvalid = '1') then
                        reg_wsel(to_integer(unsigned(RESOLVE(awaddr(decode_waddr'range))))) <= '1'; --drive register select bit in the vector   
                        decode_waddr <= unsigned(RESOLVE(awaddr(decode_waddr'range))); --once master has asserted address (awvalid is high), it should remain fixed; we can latch it here, and indicated that we have latched it
                    end if;
                elsif wr_fsm_cs = WR_RUN_s and wvalid = '1' then
                    reg_wsel(to_integer(decode_waddr)) <= '1'; --drive register select bit in the vector
                end if;

            end if;                
        end if;
    end process;   

    process (aclk)
    begin
        if rising_edge(aclk) then
            if areset = '1' then
                wready_i <= '0';
            else
                if (wvalid = '1' and wready_i = '1') then
                    wready_i <= '0';
                elsif (wr_fsm_cs = WR_RUN_s and wr_fsm_ns /= WR_RUN_s) or (wr_fsm_cs = WR_READY_s) then
                    wready_i <= '1';
                end if;
            end if;
        end if;
    end process;  

    process (aclk)
    begin
        if rising_edge(aclk) then
            if (wvalid = '1' and wready_i = '1') then --we will assert wready signal, when we have active operation and there is valid data on the bus
                wstrb_h <= unsigned(wstrb); --latch the strobe signal
                wdata_h <= unsigned(wdata); --latch the data
            end if;
        end if;
    end process;      

    process (aclk)
    begin
        if rising_edge(aclk) then
            if areset = '1' then
                bvalid_i <= '0';
            else
                if (bvalid_i = '1' and bready = '1') then --assert bvalid signal when wready is high (data will be latched)
                    bvalid_i <= '0';
                elsif (wr_fsm_cs = WR_READY_s and wr_fsm_ns = WR_RUN_s and wvalid = '1' and wready_i = '1') then
                    bvalid_i <= '1';
                elsif (wr_fsm_cs = WR_RUN_s and wvalid = '1' and wready_i = '1') then
                    bvalid_i <= '1';
                end if;

            end if;
        end if;
    end process;  

   -----------------------------------------
    --read channel
    -----------------------------------------    

    process (aclk)
    begin
        if rising_edge(aclk) then
            if areset = '1' then
                arready_i <= '0';
                arready_d <= '0';
                arvalid_d <= '0';
            else
                if (arvalid = '1' and read_busy = '0' and arready_i = '0') then
                    arready_i <= '1';
                elsif (arready_i = '1' and arvalid = '1') then --deassrert arready signal, when address has been latched
                    arready_i <= '0';
                end if;

                arready_d <= arready_i;
                arvalid_d <= arvalid;
            end if;
        end if;
    end process;   
    
    process (aclk)
    begin
        if rising_edge(aclk) then
            if areset = '1' then
                decode_raddr <= (others => '0');
            else
                if (arvalid = '1' and arready_i = '0') then
                    decode_raddr <= unsigned(RESOLVE(araddr(decode_raddr'range)));                
                end if;
            end if;
        end if;
    end process;    
    
    process (aclk)
    
    begin
        if rising_edge(aclk) then
            if ((arready_i = '1' and arvalid = '1')) then
                reg_rsel(to_integer(decode_raddr)) <= '1';
            else
                reg_rsel <= (others => '0');
            end if;
        end if;
    end process;         
    
    process (aclk)
    begin
        if rising_edge(aclk) then
            if (areset = '1') then
                rvalid_i  <= '0';
            else
                if (read_busy = '1') then
                    rvalid_i <= '1';
                end if;
                if (rvalid_i = '1' and rready = '1') then
                    rvalid_i <= '0';
                end if;
            end if;
        end if;
    end process;    
    
   process (aclk)
    begin
        if rising_edge(aclk) then
            if areset = '1' then
                read_busy       <= '0';
            else
                if (arready_i = '0' and arvalid = '1' and read_busy = '0' ) then
                    read_busy <= '1';
                elsif (rready = '1' and rvalid_i = '1') then
                    read_busy <= '0';
                end if;
            end if;
        end if;
    end process;      
    
    AXI_D32_g: if AXI_DWIDTH = 32 generate
        process (aclk)
        begin
            if rising_edge(aclk) then
                rdata <= std_logic_vector(reg_arr(to_integer(decode_raddr)));   
            end if;
        end process;
    end generate;           

    ---------------------------------------------
    -- memory logic
    ---------------------------------------------
    
    process (aclk)
    variable temp_reg : unsigned(AXI_DWIDTH-1 downto 0);    
    variable helper : unsigned(31 downto 0);
    begin
        if rising_edge(aclk) then
            if areset = '1' then
                reg_arr(get_reg_index("REG_IRQ_MASK")) <= (others => '1');
                reg_arr(get_reg_index("REG_IRQ_FLAG")) <= (others => '0');   
                reg_arr(get_reg_index("REG_SC_HCOEF")) <= resize(SCALE_CNT_ONE, 32);
                reg_arr(get_reg_index("REG_SC_VCOEF")) <= resize(SCALE_CNT_ONE, 32);
                reg_arr(get_reg_index("REG_SC_VRES")) <= to_unsigned(1920, 32);
            else
                for i in 0 to REG_ARR_SIZE-1 loop

                    if (reg_wsel(reg_description(i).register_index) = '1') then
                        if (reg_description(i).register_ro = false) then
                            temp_reg := get_reg_data(reg_arr, reg_description(i).register_name);
                            temp_reg := update_reg(temp_reg, wdata_h, wstrb_h);

                            if reg_wsel(get_reg_index("REG_IRQ_FLAG")) = '1' then --clear by writing '1'
                                for iflag in irq_flags'range loop
                                    if temp_reg(iflag) = '1' then
                                        reg_arr(get_reg_index("REG_IRQ_FLAG"))(iflag) <= '0';
                                    end if;                                
                                end loop;  
                            else
                                reg_arr(i) <= temp_reg;
                            end if;

                        end if;
                    end if;
                end loop;

                for iflag in irq_flags'range loop 
                    if irq_flags(iflag) = '1' then
                        reg_arr(get_reg_index("REG_IRQ_FLAG"))(iflag) <= '1';
                    end if;
                end loop;
            end if;
        end if;
    end process;        

    process (aclk)
        variable irq_active : std_logic;
        variable irq_flags_v : std_logic_vector(irq_flags'range);
    begin
        if rising_edge(aclk) then
            irq_active := '0';
            irq_flags_v := std_logic_vector(reg_arr(get_reg_index("REG_IRQ_FLAG"))(irq_flags_v'range));
            for i in 0 to irq_flags'left loop
                irq_active := irq_active or (irq_flags_v(i) and (not reg_arr(get_reg_index("REG_IRQ_MASK"))(i)));
            end loop;
            irq <= irq_active;
        end if;
    end process; 

    ---------------------------------------------
    -- 
    ---------------------------------------------

    scale_hor <= std_logic_vector(reg_arr(get_reg_index("REG_SC_HCOEF")));
    scale_ver <= std_logic_vector(reg_arr(get_reg_index("REG_SC_VCOEF")));
    res_ver   <= std_logic_vector(reg_arr(get_reg_index("REG_SC_VRES"))(res_ver'range));
end rtl;
