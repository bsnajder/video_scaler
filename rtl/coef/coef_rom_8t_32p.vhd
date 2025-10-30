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
-- 
-- As per CERN-OHL-P v2 section 4, should You produce hardware based on this
-- source, You must where practicable maintain the Source Location visible
-- on the external case of the product or product packaging.
-------------------------------------------------------------------------------
-- File: coef_rom_8t_32p.vhd
-- Description: 8-tap, 32-phase coefficient ROM for polyphase interpolation filter.
--              Contains pre-computed filter coefficients for 
--              with 8-tap kernel and 32-phase polyphase structure.
-- Author: Boris Snajder
-- Created: 2025
-- Modified: 2025-09-20
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;	

library utils;
use utils.utils_pkg.all;

library scale_ip;
use scale_ip.coef_8T_32P_pkg.all;

entity coef_8t_32p_rom is
    generic (
        TAP_SEL     : integer := 0
    );
    port (
        addr        : in std_logic_vector(log2(32)-1 downto 0);
        data        : out std_logic_vector(16-1 downto 0)
    );
    
end entity coef_8t_32p_rom;

architecture rtl of coef_8t_32p_rom is

    signal rom_data :  coef_rom_arr_t := TAP_8_COEF_ROM(TAP_SEL);

begin

    process (addr)
    begin
        data <= std_logic_vector(rom_data(to_integer(unsigned(RESOLVE(addr)))));
    end process;

end architecture rtl;
