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
-- File: scale_rom_8_32.vhd
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

package coef_8T_32P_pkg is


    type coef_rom_arr_t is array (0 to 31) of signed(15 downto 0);
    type coef_rom_8_t is array (0 to 7) of coef_rom_arr_t;

    constant ROM_TAP_8_7 : coef_rom_arr_t := (
        X"0000", X"0000", X"0000", X"FFFF", X"FFFF", X"FFFE", X"FFFC", X"FFFA", 
        X"FFF7", X"FFF3", X"FFEE", X"FFE9", X"FFE3", X"FFDD", X"FFD6", X"FFCF", 
        X"FFC7", X"FFC0", X"FFB9", X"FFB2", X"FFAC", X"FFA7", X"FFA3", X"FFA1", 
        X"FFA0", X"FFA2", X"FFA7", X"FFAE", X"FFB8", X"FFC5", X"FFD5", X"FFE9"
    );

    constant ROM_TAP_8_6 : coef_rom_arr_t := (
        X"0000", X"001B", X"0039", X"005A", X"007F", X"00A6", X"00D0", X"00FC", 
        X"012A", X"0159", X"0188", X"01B7", X"01E5", X"0212", X"023B", X"0262", 
        X"0284", X"02A1", X"02B8", X"02C8", X"02D0", X"02D0", X"02C6", X"02B2", 
        X"0294", X"026A", X"0235", X"01F4", X"01A8", X"014F", X"00EB", X"007B"
    );

    constant ROM_TAP_8_5 : coef_rom_arr_t := (
        X"0000", X"FF7B", X"FEED", X"FE56", X"FDB8", X"FD14", X"FC6B", X"FBC1", 
        X"FB15", X"FA6A", X"F9C3", X"F921", X"F887", X"F7F7", X"F774", X"F6FF", 
        X"F69C", X"F64D", X"F614", X"F5F4", X"F5EE", X"F605", X"F63B", X"F691", 
        X"F709", X"F7A5", X"F865", X"F94B", X"FA56", X"FB88", X"FCE0", X"FE5D"
    );

    constant ROM_TAP_8_4 : coef_rom_arr_t := (
        X"0000", X"01C7", X"03B1", X"05BC", X"07E6", X"0A2D", X"0C8F", X"0F09", 
        X"1197", X"1436", X"16E3", X"1999", X"1C56", X"1F15", X"21D1", X"2486", 
        X"2731", X"29CD", X"2C56", X"2EC7", X"311C", X"3352", X"3564", X"3750", 
        X"3911", X"3AA5", X"3C09", X"3D3B", X"3E38", X"3EFE", X"3F8D", X"3FE3"
    );

    constant ROM_TAP_8_3 : coef_rom_arr_t := (
        X"4000", X"3FE3", X"3F8D", X"3EFE", X"3E38", X"3D3B", X"3C09", X"3AA5", 
        X"3911", X"3750", X"3564", X"3352", X"311C", X"2EC7", X"2C56", X"29CD", 
        X"2731", X"2486", X"21D1", X"1F15", X"1C56", X"1999", X"16E3", X"1436", 
        X"1197", X"0F09", X"0C8F", X"0A2D", X"07E6", X"05BC", X"03B1", X"01C7"
    );

    constant ROM_TAP_8_2 : coef_rom_arr_t := (
        X"0000", X"FE5D", X"FCE0", X"FB88", X"FA56", X"F94B", X"F865", X"F7A5", 
        X"F709", X"F691", X"F63B", X"F605", X"F5EE", X"F5F4", X"F614", X"F64D", 
        X"F69C", X"F6FF", X"F774", X"F7F7", X"F887", X"F921", X"F9C3", X"FA6A", 
        X"FB15", X"FBC1", X"FC6B", X"FD14", X"FDB8", X"FE56", X"FEED", X"FF7B"
    );

    constant ROM_TAP_8_1 : coef_rom_arr_t := (
        X"0000", X"007B", X"00EB", X"014F", X"01A8", X"01F4", X"0235", X"026A", 
        X"0294", X"02B2", X"02C6", X"02D0", X"02D0", X"02C8", X"02B8", X"02A1", 
        X"0284", X"0262", X"023B", X"0212", X"01E5", X"01B7", X"0188", X"0159", 
        X"012A", X"00FC", X"00D0", X"00A6", X"007F", X"005A", X"0039", X"001B"
    );

    constant ROM_TAP_8_0 : coef_rom_arr_t := (
        X"0000", X"FFE9", X"FFD5", X"FFC5", X"FFB8", X"FFAE", X"FFA7", X"FFA2", 
        X"FFA0", X"FFA1", X"FFA3", X"FFA7", X"FFAC", X"FFB2", X"FFB9", X"FFC0", 
        X"FFC7", X"FFCF", X"FFD6", X"FFDD", X"FFE3", X"FFE9", X"FFEE", X"FFF3", 
        X"FFF7", X"FFFA", X"FFFC", X"FFFE", X"FFFF", X"FFFF", X"0000", X"0000"
    );

    constant TAP_8_COEF_ROM : coef_rom_8_t := (
        ROM_TAP_8_0, 
        ROM_TAP_8_1, 
        ROM_TAP_8_2, 
        ROM_TAP_8_3, 
        ROM_TAP_8_4, 
        ROM_TAP_8_5, 
        ROM_TAP_8_6, 
        ROM_TAP_8_7
    );

end package coef_8T_32P_pkg;
