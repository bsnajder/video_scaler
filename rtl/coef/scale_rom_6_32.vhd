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
-- File: scale_rom_6_32.vhd
-- Description: 6-tap, 32-phase coefficient ROM for polyphase interpolation filter.
--              Contains pre-computed filter coefficients for 
--              with 6-tap kernel and 32-phase polyphase structure.
-- Author: Boris Snajder
-- Created: 2025
-- Modified: 2025-09-20
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package coef_6T_32P_pkg is


    type coef_rom_arr_t is array (0 to 31) of signed(15 downto 0);
    type coef_rom_6_t is array (0 to 5) of coef_rom_arr_t;

    constant ROM_TAP_6_5 : coef_rom_arr_t := (
        X"0000", X"0000", X"0000", X"0001", X"0003", X"0006", X"000A", X"0010", 
        X"0017", X"0020", X"002B", X"0037", X"0046", X"0056", X"0067", X"0079", 
        X"008C", X"009F", X"00B1", X"00C2", X"00D2", X"00DF", X"00E9", X"00EF", 
        X"00F0", X"00EC", X"00E2", X"00D0", X"00B8", X"0097", X"006E", X"003B"
    );

    constant ROM_TAP_6_4 : coef_rom_arr_t := (
        X"0000", X"FFBB", X"FF6E", X"FF17", X"FEB7", X"FE50", X"FDE2", X"FD6D", 
        X"FCF3", X"FC76", X"FBF6", X"FB76", X"FAF7", X"FA7C", X"FA06", X"F999", 
        X"F936", X"F8DF", X"F899", X"F864", X"F843", X"F83A", X"F84A", X"F876", 
        X"F8BF", X"F929", X"F9B4", X"FA62", X"FB36", X"FC2E", X"FD4D", X"FE93"
    );

    constant ROM_TAP_6_3 : coef_rom_arr_t := (
        X"0000", X"0193", X"034C", X"052A", X"072B", X"094D", X"0B8F", X"0DED", 
        X"1065", X"12F3", X"1595", X"1845", X"1B01", X"1DC3", X"2087", X"2349", 
        X"2604", X"28B2", X"2B51", X"2DD9", X"3048", X"3297", X"34C4", X"36C9", 
        X"38A3", X"3A4F", X"3BC8", X"3D0D", X"3E1A", X"3EED", X"3F85", X"3FE1"
    );

    constant ROM_TAP_6_2 : coef_rom_arr_t := (
        X"4000", X"3FE1", X"3F85", X"3EED", X"3E1A", X"3D0D", X"3BC8", X"3A4F", 
        X"38A3", X"36C9", X"34C4", X"3297", X"3048", X"2DD9", X"2B51", X"28B2", 
        X"2604", X"2349", X"2087", X"1DC3", X"1B01", X"1845", X"1595", X"12F3", 
        X"1065", X"0DED", X"0B8F", X"094D", X"072B", X"052A", X"034C", X"0193"
    );

    constant ROM_TAP_6_1 : coef_rom_arr_t := (
        X"0000", X"FE93", X"FD4D", X"FC2E", X"FB36", X"FA62", X"F9B4", X"F929", 
        X"F8BF", X"F876", X"F84A", X"F83A", X"F843", X"F864", X"F899", X"F8DF", 
        X"F936", X"F999", X"FA06", X"FA7C", X"FAF7", X"FB76", X"FBF6", X"FC76", 
        X"FCF3", X"FD6D", X"FDE2", X"FE50", X"FEB7", X"FF17", X"FF6E", X"FFBB"
    );

    constant ROM_TAP_6_0 : coef_rom_arr_t := (
        X"0000", X"003B", X"006E", X"0097", X"00B8", X"00D0", X"00E2", X"00EC", 
        X"00F0", X"00EF", X"00E9", X"00DF", X"00D2", X"00C2", X"00B1", X"009F", 
        X"008C", X"0079", X"0067", X"0056", X"0046", X"0037", X"002B", X"0020", 
        X"0017", X"0010", X"000A", X"0006", X"0003", X"0001", X"0000", X"0000"
    );

    constant TAP_6_COEF_ROM : coef_rom_6_t := (
        ROM_TAP_6_0, 
        ROM_TAP_6_1, 
        ROM_TAP_6_2, 
        ROM_TAP_6_3, 
        ROM_TAP_6_4, 
        ROM_TAP_6_5
    );

end package coef_6T_32P_pkg;
