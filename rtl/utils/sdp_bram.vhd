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
-- File: sdp_bram.vhd
-- Description: Simple dual-port Block RAM implementation with configurable
--              read/write widths.
-- Author: Boris Snajder
-- Created: 2025
-- Modified: 2025-09-20
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library utils;
use utils.utils_pkg.all;

entity sdp_bram is
generic (
    WDWIDTH		: positive      := 8;	
    RDWIDTH		: positive      := 8;	
    WDEPTH		: positive      := 16
);
port (
    clka 		: in std_logic;
    ena 		: in std_logic;
    wea 		: in std_logic;
    addra 		: in std_logic_vector(LOG2(WDEPTH)-1 downto 0);
    dina 		: in std_logic_vector(WDWIDTH-1 downto 0);
    clkb 		: in std_logic;
    enb 		: in std_logic;
    addrb 		: in std_logic_vector(LOG2(WDEPTH*WDWIDTH/RDWIDTH)-1 downto 0);
    doutb 		: out std_logic_vector(RDWIDTH-1 downto 0)
);
end sdp_bram;

architecture rtl of sdp_bram is

constant minWIDTH : integer := utils.utils_pkg.min(integer(WDWIDTH), integer(RDWIDTH));
constant maxWIDTH : integer := max(WDWIDTH, RDWIDTH);
constant RATIO    : integer := maxWIDTH / minWIDTH;
constant ramSIZE  : integer := ite(maxWIDTH = WDWIDTH, WDEPTH, WDEPTH * RATIO);

type ram_type is array (0 to ramSIZE - 1) of std_logic_vector(minWIDTH - 1 downto 0);
signal ram_mem : ram_type;-- := (others => (others => '0'));

signal readB : std_logic_vector(RDWIDTH - 1 downto 0) := (others => '0');
signal regB : std_logic_vector(RDWIDTH - 1 downto 0) := (others => '0');

begin

-- Write process
gen_WR_WIDER: if WDWIDTH >= RDWIDTH generate
    process(clkA)
    begin
        if rising_edge(clkA) then
            if ena = '1' then
                if wea = '1' then
                    ram_mem(to_integer(unsigned(addra))) <= dina;
                end if;
            end if;
        end if;
    end process;

    -- Read process
    process(clkB)
    begin
        if rising_edge(clkB) then
            for i in 0 to RATIO - 1 loop
                if enB = '1' then
                    readB((i + 1) * minWIDTH - 1 downto i * minWIDTH) <= ram_mem(to_integer(unsigned(addrb) & to_unsigned(i, log2(RATIO))));
                end if;
            end loop;
            
        end if;
    end process;

    doutb <= readB;
end generate;

gen_RD_WIDER: if WDWIDTH < RDWIDTH generate
    process(clkA)
    begin
        if rising_edge(clkA) then
            for i in 0 to RATIO - 1 loop
                if ena = '1' then
                    if wea = '1' then
                        ram_mem(to_integer(unsigned(addra) & to_unsigned(i, log2(RATIO)))) <= dina((i + 1) * minWIDTH - 1 downto i * minWIDTH);
                    end if;
                end if;
            end loop;
        end if;
    end process;

    -- read process
    process(clkB)
    begin
        if rising_edge(clkB) then
            if enB = '1' then
                readB <= ram_mem(to_integer(unsigned(addrb)));
            end if;
            
        end if;
    end process;

    doutb <= readB;
end generate;

end rtl;		