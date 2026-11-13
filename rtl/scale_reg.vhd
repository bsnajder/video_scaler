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

    signal awready_i                : std_logic;
    signal wready_i                 : std_logic;
    signal bvalid_i                 : std_logic := '0';
    signal arready_i                : std_logic;
    signal rvalid_i                 : std_logic := '0';

    signal aw_done                  : std_logic := '0'; --write address accepted, waiting for write to complete
    signal w_done                   : std_logic := '0'; --write data accepted, waiting for write to complete

    signal wstrb_h                  : unsigned(AXI_DWIDTH/8-1 downto 0);
    signal wdata_h                  : unsigned(AXI_DWIDTH-1 downto 0);

    signal irq_flags                : std_logic_vector(0 downto 0);

    -- one-hot register select for a decoded address; all zeros for unmapped addresses
    function addr_to_sel(addr : unsigned) return unsigned is
        variable sel : unsigned(REG_ARR_SIZE-1 downto 0) := (others => '0');
    begin
        if to_integer(addr) < REG_ARR_SIZE then
            sel(to_integer(addr)) := '1';
        end if;
        return sel;
    end addr_to_sel;

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
    -- AW and W are accepted independently and in any order (AXI allows either
    -- channel to arrive first). The register write and BVALID happen once both
    -- have been accepted. Neither channel accepts a new beat until the pending
    -- response has been taken, so decode_waddr/wdata_h/wstrb_h stay stable
    -- while reg_wsel is applied.
    awready_i <= not aw_done and not bvalid_i;
    wready_i  <= not w_done  and not bvalid_i;

    process (aclk)
    begin
        if rising_edge(aclk) then
            reg_wsel <= (others => '0');
            if areset = '1' then
                aw_done  <= '0';
                w_done   <= '0';
                bvalid_i <= '0';
            else
                if (awvalid = '1' and awready_i = '1') then
                    decode_waddr <= unsigned(RESOLVE(awaddr(decode_waddr'range)));
                    aw_done      <= '1';
                end if;

                if (wvalid = '1' and wready_i = '1') then
                    wstrb_h <= unsigned(wstrb);
                    wdata_h <= unsigned(wdata);
                    w_done  <= '1';
                end if;

                if (aw_done = '1' and w_done = '1') then
                    reg_wsel <= addr_to_sel(decode_waddr); --writes to unmapped addresses are ignored
                    aw_done  <= '0';
                    w_done   <= '0';
                    bvalid_i <= '1';
                elsif (bvalid_i = '1' and bready = '1') then
                    bvalid_i <= '0';
                end if;
            end if;
        end if;
    end process;

    -----------------------------------------
    --read channel
    -----------------------------------------
    -- Register data is captured on the AR handshake and held until the R
    -- handshake, so RDATA is stable while RVALID is high. A new address is
    -- not accepted while a read response is outstanding.
    arready_i <= not rvalid_i;

    process (aclk)
        variable raddr : unsigned(REG_ARR_DEC_RANGE);
    begin
        if rising_edge(aclk) then
            reg_rsel <= (others => '0');
            if areset = '1' then
                rvalid_i     <= '0';
                decode_raddr <= (others => '0');
            else
                if (arvalid = '1' and arready_i = '1') then
                    raddr        := unsigned(RESOLVE(araddr(decode_raddr'range)));
                    decode_raddr <= raddr;
                    reg_rsel     <= addr_to_sel(raddr);
                    rvalid_i     <= '1';
                elsif (rvalid_i = '1' and rready = '1') then
                    rvalid_i <= '0';
                end if;
            end if;
        end if;
    end process;

    AXI_D32_g: if AXI_DWIDTH = 32 generate
        process (aclk)
            variable raddr : unsigned(REG_ARR_DEC_RANGE);
        begin
            if rising_edge(aclk) then
                if (arvalid = '1' and arready_i = '1') then
                    raddr := unsigned(RESOLVE(araddr(decode_raddr'range)));
                    if to_integer(raddr) < REG_ARR_SIZE then
                        rdata <= std_logic_vector(reg_arr(to_integer(raddr)));
                    else
                        rdata <= (others => '0'); --unmapped address
                    end if;
                end if;
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
                                    --only bits actually written as '1' clear a flag; temp_reg would also
                                    --contain the current (set) flag value for bytes not enabled by wstrb
                                    if wstrb_h(iflag/8) = '1' and wdata_h(iflag) = '1' then
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
