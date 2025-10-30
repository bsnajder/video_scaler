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
-- File: scale_pkg.vhd
-- Description: Package containing constants, types, and function declarations
--              for the video scaler IP. Defines tap numbers, engine counts,
--              and data structures for scaling operations.
-- Author: Boris Snajder
-- Created: 2025
-- Modified: 2025-09-20
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library utils;
use utils.utils_pkg.all;

package scale_pkg is

    -- Constants
    constant TAP_NUM        : integer := 6; -- Number of taps for interpolator engine, (supported values are 6 and 8))
    constant TAP_CENTER     : integer := TAP_NUM / 2-1;
    constant PHASE_NUM      : integer := 32; -- Number of phases
    constant ENG_NUM        : integer := 2; -- Number of engines, supported values are 1 and 2

    constant LINE_SIZE      : integer := 4096; -- how many pixels we can store in on line buffer, in the vertical scaler

    type coef_rom_out_t is array (TAP_NUM-1 downto 0) of std_logic_vector(16-1 downto 0);

    --but we need to make sure that we will have proper alignment -> our registers will behave as shift register, with shift equal to number of ENG_NUM
    --we need to make sure that those will align to center taps, thus we need to have multiple of ENG_NUM 
    constant TAP_NUM_LEFT   : integer := TAP_NUM / 2 - 1; -- Number of taps to the left
    constant TAP_NUM_RIGHT  : integer := TAP_NUM / 2; -- Number of taps to the right

    constant REG_NUM_HLP    : integer := TAP_NUM + ENG_NUM - 1; --how many registers we need to store data

    constant TAP_REG_NUM    : integer :=ite( (REG_NUM_HLP - TAP_NUM_LEFT) mod ENG_NUM = 0, REG_NUM_HLP+1, REG_NUM_HLP + ENG_NUM - (REG_NUM_HLP - TAP_NUM_LEFT) mod ENG_NUM + 1); --how many registers we need to store data, we need one more register to keep data for mirroring at the end of the process

    -- Type definitions
    type tap_t          is array (0 to TAP_REG_NUM-1) of std_logic_vector(7 downto 0); --pixel is 8 bits
    type tap_arr_t      is array (0 to 2) of tap_t; --we have array 0 to 0, for debug, later for RGB we shall change this
    subtype tap_off_ptr_t  is signed(4 downto 0); --4 downto 0 is engouh to handle up to 16 taps
    type tap_ptr_t      is array (0 to TAP_REG_NUM-1) of tap_off_ptr_t; 
    type tap_last_ptr_t is array (0 to ENG_NUM-1)     of tap_off_ptr_t;
    type tap_ptr_comp_t is array (0 to TAP_REG_NUM+TAP_NUM/2-1) of tap_off_ptr_t;

    type eng_data_tap_t is array (0 to TAP_NUM-1+1) of std_logic_vector(7 downto 0); --pixel is 8 bits
    type eng_data_arr_t is array (0 to 2) of eng_data_tap_t; 
    type eng_data_t     is array (0 to ENG_NUM-1) of eng_data_arr_t; --we have array 0 to 0, for debug, later for RGB we shall change this

    constant SCALE_CNT_SIZE         : integer := 28; --number of bits for scale counter
    constant SCALE_CNT_FRAC_SIZE    : integer := 22; --number of bits for scale counter fraction
    constant SCALE_CNT_ONE          : unsigned(SCALE_CNT_SIZE-1 downto 0) := to_unsigned(2**SCALE_CNT_FRAC_SIZE, SCALE_CNT_SIZE);

    type scale_cnt_t is array (0 to ENG_NUM-1) of unsigned(SCALE_CNT_SIZE-1 downto 0); --counter for scaling

    -- Function declaration
    function get_tap_init_ptr return tap_ptr_comp_t;
    function get_tap_last_ptr return tap_ptr_comp_t;
    procedure calc_next_phase (curr_phase : in unsigned(SCALE_CNT_SIZE-1 downto 0);
                               inc_phase  : in unsigned(SCALE_CNT_SIZE-1 downto 0);
                               next_phase : out unsigned(SCALE_CNT_SIZE-1 downto 0);
                               scaler_run  : out std_logic;
                               scaler_stall  : out std_logic); 

end scale_pkg;


-- Implementation of the function get_tap_init_ptr
package body scale_pkg is

    -- this function will return offset of the data in the tap register for mirroring during start of the process
    function get_tap_init_ptr return tap_ptr_comp_t is
        variable tap_ptr_init : tap_ptr_comp_t;
        variable init_curr_ptr : signed(tap_ptr_init(0)'range);
    begin

        tap_ptr_init := (others => (others => '0'));
        init_curr_ptr := to_signed(2, tap_ptr_init(0)'length);
        --for i in tap_ptr_t'right-(ENG_NUM) downto tap_ptr_t'right-(ENG_NUM)-TAP_NUM_LEFT loop
        for i in TAP_REG_NUM-1 downto TAP_REG_NUM-1-(TAP_NUM_LEFT-1) loop
            tap_ptr_init(i) := init_curr_ptr;
            init_curr_ptr := init_curr_ptr + to_signed(2, tap_ptr_init(0)'length);
        end loop;

        return tap_ptr_init;
    end function;

    -- this function will return offset of the data in the tap register for mirroring at the end of the process
    function get_tap_last_ptr return tap_ptr_comp_t is
        variable tap_ptr_last : tap_ptr_comp_t;
        variable tap_ptr_value : signed(tap_ptr_last(0)'range);
    begin
        tap_ptr_last := (others => (others => '0'));
        tap_ptr_value := to_signed(-2, tap_ptr_last(0)'length);
        for i in TAP_REG_NUM to TAP_REG_NUM+TAP_NUM/2-1 loop
            tap_ptr_last(i) := tap_ptr_value;
            tap_ptr_value := tap_ptr_value - 2;
        end loop;

        return tap_ptr_last;
    end function;

    procedure calc_next_phase (curr_phase    : in unsigned(SCALE_CNT_SIZE-1 downto 0);
                               inc_phase     : in unsigned(SCALE_CNT_SIZE-1 downto 0);
                               next_phase    : out unsigned(SCALE_CNT_SIZE-1 downto 0);
                               scaler_run    : out std_logic;
                               scaler_stall  : out std_logic) 
    is
        variable next_calc_delta        : unsigned(SCALE_CNT_SIZE-1 downto 0);
        variable next_calc_delta_one    : unsigned(SCALE_CNT_SIZE-1 downto 0);
        variable next_calc_one          : unsigned(SCALE_CNT_SIZE-1 downto 0);
    begin
        next_calc_one(SCALE_CNT_FRAC_SIZE-1 downto 0) := curr_phase(SCALE_CNT_FRAC_SIZE-1 downto 0);
        next_calc_one(SCALE_CNT_SIZE-1 downto SCALE_CNT_FRAC_SIZE) := curr_phase(SCALE_CNT_SIZE-1 downto SCALE_CNT_FRAC_SIZE) - SCALE_CNT_ONE(SCALE_CNT_SIZE-1 downto SCALE_CNT_FRAC_SIZE);
        next_calc_delta_one := next_calc_one + inc_phase;
        next_calc_delta := curr_phase + inc_phase;

        next_phase := next_calc_delta;
        scaler_stall := '0';

        if next_calc_one(next_calc_one'left) = '0' then --curr_phase >= 1
            next_phase := next_calc_one;
            scaler_run := '0';
        else
            scaler_run := '1';
        end if;

        if next_calc_one(next_calc_one'left) = '1' and
           next_calc_delta(SCALE_CNT_SIZE-1 downto SCALE_CNT_FRAC_SIZE) /= to_unsigned(0, SCALE_CNT_SIZE-SCALE_CNT_FRAC_SIZE) then --curr_phase < 1 && (curr_phase + inc_phase) >= 1 
            next_phase := next_calc_delta_one;
        end if;

        if next_calc_one(next_calc_one'left) = '1' and
           next_calc_delta(SCALE_CNT_SIZE-1 downto SCALE_CNT_FRAC_SIZE) = to_unsigned(0, SCALE_CNT_SIZE-SCALE_CNT_FRAC_SIZE) then --curr_phase < 1 && (curr_phase + inc_phase) < 1 
            next_phase := next_calc_delta;
            scaler_stall := '1';
        end if;

    end procedure;

end scale_pkg;
