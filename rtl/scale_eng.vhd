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
-- File: scale_eng.vhd
-- Description: Scaling engine core implementing polyphase interpolation filter
--              with configurable tap coefficients. Supports 6-tap and 8-tap
--              configurations with 32-phase polyphase structure.
-- Author: Boris Snajder
-- Created: 2025
-- Modified: 2025-09-20
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
-- synthesis translate_off
--use ieee.fixed_pkg.all;
-- synthesis translate_on


Library UNISIM;
use UNISIM.vcomponents.all;

library utils;
use utils.utils_pkg.all;

library scale_ip;
use scale_ip.scale_pkg.all;


entity scale_eng is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        --
        data_in         : in  std_logic_vector(3*TAP_NUM*8-1 downto 0);
        data_in_val     : in  std_logic;
        data_in_last    : in  std_logic;
        data_in_user    : in  std_logic;
        phase_in        : in  std_logic_vector(1*log2(PHASE_NUM)-1 downto 0);

        data_out        : out std_logic_vector(3*8-1 downto 0);
        data_out_val    : out std_logic;
        data_out_user   : out std_logic;
        data_out_last   : out std_logic

    );
end entity scale_eng;

architecture rtl of scale_eng is

    type rom_addr_arr_t is array(0 downto 0) of std_logic_vector(log2(PHASE_NUM)-1 downto 0);
    signal phase_addr     : rom_addr_arr_t;    

    type rom_arr_t  is array(0 downto 0) of coef_rom_out_t;
    signal coef_rom_arr  : rom_arr_t;

    type mult_coef_t        is array(0 to TAP_NUM-1) of std_logic_vector(29 downto 0);
    type mult_coef_arr_t    is array(0 to 0) of mult_coef_t;
    signal mult_coef        : mult_coef_arr_t;

    type mult_data_t        is array(0 to TAP_NUM-1) of std_logic_vector(17 downto 0);
    type mult_data_arr_t    is array(0 to 2) of mult_data_t;
    signal mult_data        : mult_data_arr_t;

    type mult_res_t         is array(0 to TAP_NUM-1) of std_logic_vector(47 downto 0);
    type mult_res_arr_t     is array(0 to 2) of mult_res_t;
    signal mult_res         : mult_res_arr_t;

    type scale_res_t        is array(0 to 2) of std_logic_vector(7 downto 0);
    signal scale_res        : scale_res_t;

    signal mult_res_val     : std_logic_vector(1 downto 0);
    signal mult_res_last    : std_logic_vector(1 downto 0);
    signal mult_res_user    : std_logic_vector(1 downto 0);
    signal first_data       : std_logic := '1';

    -- synthesis translate_off
    --type tap_scale_coef_fix_t is array(0 to TAP_NUM-1) of sfixed(1 downto -14);
    --signal tap_scale_coef_fix : tap_scale_coef_fix_t;
    -- synthesis translate_on
    
begin

    process (phase_in)
    begin
        for i in 1-1 downto 0 loop
            phase_addr(i) <= phase_in((i+1)*log2(PHASE_NUM)-1 downto i*log2(PHASE_NUM));
        end loop;
    end process;

  -- instantiate ROMs
  u_eng_tap_coef_gen: for j in 1-1 downto 0 generate
      u_tap_rom_gen: for i in TAP_NUM-1 downto 0 generate

          u_rom_sel6_gen: if TAP_NUM =6 and PHASE_NUM = 32 generate
              u_tap_rom: entity scale_ip.coef_6t_32p_rom 
              generic map(
                 TAP_SEL     => i
             )
              port map
              (
                  addr        => phase_addr(j),
                  data        => coef_rom_arr(j)(i)
              );
          end generate;

          u_rom_sel8_gen: if TAP_NUM =8 and PHASE_NUM = 32 generate
              u_tap_rom: entity scale_ip.coef_8t_32p_rom 
              generic map(
                 TAP_SEL     => i
             )
              port map
              (
                  addr        => phase_addr(j),
                  data        => coef_rom_arr(j)(i)
              );
          end generate;          
        
        -- synthesis translate_off
        --fix_gen: if j = 0 generate
        --    tap_scale_coef_fix(i) <= to_sfixed(coef_rom_arr(j)(i), 1, -14); 
        --end generate;
        -- synthesis translate_on

        mult_coef(j)(i) <= std_logic_vector(shift_left(resize(signed(coef_rom_arr(j)(i)), 30), 27-16)); --A input of DSP48E2 is 30 bits wide, but multiplier is 27x18
    end generate;
   end generate;
    
   
    tap_mult_gen: for i in TAP_NUM-1 downto 0 generate

        data_in_gen: for col_idx in 0 to 2 generate
            mult_data(col_idx)(i) <= std_logic_vector(shift_left(resize(unsigned(data_in((col_idx*TAP_NUM+i+1)*8-1 downto (col_idx*TAP_NUM+i)*8)), 18), 18-8-1)); --B input of DSP48E2 is 18 bits wide (signed), but multiplier is 27x18
        --DSP48E1_inst : DSP48E1
        DSP48E2_inst : DSP48E2
           generic map (
              -- Feature Control Attributes: Data Path Selection
              AMULTSEL              => "A",
              A_INPUT               => "DIRECT",               -- Selects A input source, "DIRECT" (A port) or "CASCADE" (ACIN port)
              B_INPUT               => "DIRECT",               -- Selects B input source, "DIRECT" (B port) or "CASCADE" (BCIN port)
              --USE_DPORT         => FALSE,                -- Select D port usage (TRUE or FALSE)
              PREADDINSEL           => "A",                -- Selects input to pre-adder (A, B)
              RND                   => X"000000000000",            -- Rounding Constant
              USE_MULT              => "MULTIPLY",            -- Select multiplier usage ("MULTIPLY", "DYNAMIC", or "NONE")
              USE_SIMD              => "ONE48",               -- SIMD selection ("ONE48", "TWO24", "FOUR12")
              USE_WIDEXOR           => "FALSE",            -- Use the Wide XOR function (FALSE, TRUE)
              XORSIMD               => "XOR24_48_96",          -- Mode of operation for the Wide XOR (XOR12, XOR24_48_96)
              -- Pattern Detector Attributes: Pattern Detection Configuration
              AUTORESET_PATDET      => "NO_RESET",    -- "NO_RESET", "RESET_MATCH", "RESET_NOT_MATCH" 
              MASK                  => X"3fffffffffff",           -- 48-bit mask value for pattern detect (1=ignore)
              PATTERN               => X"000000000000",        -- 48-bit pattern match for pattern detect
              SEL_MASK              => "MASK",                -- "C", "MASK", "ROUNDING_MODE1", "ROUNDING_MODE2" 
              SEL_PATTERN           => "PATTERN",          -- Select pattern value ("PATTERN" or "C")
              USE_PATTERN_DETECT    => "NO_PATDET", -- Enable pattern detect ("PATDET" or "NO_PATDET")
              -- Programmable Inversion Attributes: Specifies built-in programmable inversion on specific pins
             IS_ALUMODE_INVERTED    => "0000",     -- Optional inversion for ALUMODE
             IS_CARRYIN_INVERTED    => '0',        -- Optional inversion for CARRYIN
             IS_CLK_INVERTED        => '0',            -- Optional inversion for CLK
             IS_INMODE_INVERTED     => "00000",     -- Optional inversion for INMODE
             IS_OPMODE_INVERTED     => "000000000", -- Optional inversion for OPMODE
             IS_RSTALLCARRYIN_INVERTED => '0',  -- Optional inversion for RSTALLCARRYIN
             IS_RSTALUMODE_INVERTED => '0',     -- Optional inversion for RSTALUMODE
             IS_RSTA_INVERTED       => '0',           -- Optional inversion for RSTA
             IS_RSTB_INVERTED       => '0',           -- Optional inversion for RSTB
             IS_RSTCTRL_INVERTED    => '0',        -- Optional inversion for RSTCTRL
             IS_RSTC_INVERTED       => '0',           -- Optional inversion for RSTC
             IS_RSTD_INVERTED       => '0',           -- Optional inversion for RSTD
             IS_RSTINMODE_INVERTED  => '0',      -- Optional inversion for RSTINMODE
             IS_RSTM_INVERTED       => '0',           -- Optional inversion for RSTM
             IS_RSTP_INVERTED       => '0',           -- Optional inversion for RSTP
              -- Register Control Attributes: Pipeline Register Configuration
              ACASCREG              => 1,                     -- Number of pipeline stages between A/ACIN and ACOUT (0, 1 or 2)
              ADREG                 => 0,                        -- Number of pipeline stages for pre-adder (0 or 1)
              ALUMODEREG            => 0,                   -- Number of pipeline stages for ALUMODE (0 or 1)
              AREG                  => 1,                         -- Number of pipeline stages for A (0, 1 or 2)
              BCASCREG              => 1,                     -- Number of pipeline stages between B/BCIN and BCOUT (0, 1 or 2)
              BREG                  => 1,                         -- Number of pipeline stages for B (0, 1 or 2)
              CARRYINREG            => 0,                   -- Number of pipeline stages for CARRYIN (0 or 1)
              CARRYINSELREG         => 0,                -- Number of pipeline stages for CARRYINSEL (0 or 1)
              CREG                  => 0,                         -- Number of pipeline stages for C (0 or 1)
              DREG                  => 0,                         -- Number of pipeline stages for D (0 or 1)
              INMODEREG             => 0,                    -- Number of pipeline stages for INMODE (0 or 1)
              MREG                  => 0,                         -- Number of multiplier pipeline stages (0 or 1)
              OPMODEREG             => 0,                    -- Number of pipeline stages for OPMODE (0 or 1)
              PREG                  => 1                          -- Number of pipeline stages for P (0 or 1)
           )
           port map (
              -- Cascade: 30-bit (each) output: Cascade Ports
              ACOUT                 => open,                   -- 30-bit output: A port cascade output
              BCOUT                 => open,                   -- 18-bit output: B port cascade output
              CARRYCASCOUT          => open,     -- 1-bit output: Cascade carry output
              MULTSIGNOUT           => open,       -- 1-bit output: Multiplier sign cascade output
              PCOUT                 => open,                   -- 48-bit output: Cascade output
              -- Control: 1-bit (each) output: Control Inputs/Status Bits
              OVERFLOW              => open,             -- 1-bit output: Overflow in add/acc output
              PATTERNBDETECT        => open, -- 1-bit output: Pattern bar detect output
              PATTERNDETECT         => open,   -- 1-bit output: Pattern detect output
              UNDERFLOW             => open,           -- 1-bit output: Underflow in add/acc output
              -- Data: 4-bit (each) output: Data Ports
              CARRYOUT              => open,             -- 4-bit output: Carry output
              P                     => mult_res(col_idx)(i),                           -- 48-bit output: Primary data output
              -- Cascade: 30-bit (each) input: Cascade Ports
              ACIN                  => "000000000000000000000000000000",                     -- 30-bit input: A cascade data input
              BCIN                  => "000000000000000000",                     -- 18-bit input: B cascade input
              CARRYCASCIN           => '0',       -- 1-bit input: Cascade carry input
              MULTSIGNIN            => '0',         -- 1-bit input: Multiplier sign input
              PCIN                  => x"000000000000",                     -- 48-bit input: P cascade input
              -- Control: 4-bit (each) input: Control Inputs/Status Bits
              ALUMODE               => "0000",               -- 4-bit input: ALU control input (ALU mode 0000 = Z+W+X+Y+CIN)
              CARRYINSEL            => "000",         -- 3-bit input: Carry select input
              CLK                   => clk,                    -- 1-bit input: Clock input
              --INMODE                => "00000",                 -- 5-bit input: INMODE control input
              INMODE                => "10001",                 -- 5-bit input: INMODE control input
              OPMODE                => "000000101",                 -- 9-bit input: Operation mode input (000000101 => X mux Out = M, Y mux Out = M  )
              -- Data: 30-bit (each) input: Data Ports
              A                     => mult_coef(0)(i),                           -- 30-bit input: A data input
              B                     => mult_data(col_idx)(i),                           -- 18-bit input: B data input
              C                     => x"000000000000",                           -- 48-bit input: C data input
              CARRYIN               => '0',               -- 1-bit input: Carry input signal
              D                     => (others => '0'),                           -- 25-bit input: D data input
              -- Reset/Clock Enable: 1-bit (each) input: Reset/Clock Enable Inputs
              CEA1                  => '1',                     -- 1-bit input: Clock enable input for 1st stage AREG
              CEA2                  => '0',                     -- 1-bit input: Clock enable input for 2nd stage AREG
              CEAD                  => '0',                     -- 1-bit input: Clock enable input for ADREG
              CEALUMODE             => '0',           -- 1-bit input: Clock enable input for ALUMODE
              CEB1                  => '1',                     -- 1-bit input: Clock enable input for 1st stage BREG
              CEB2                  => '0',                     -- 1-bit input: Clock enable input for 2nd stage BREG
              CEC                   => '0',                       -- 1-bit input: Clock enable input for CREG
              CECARRYIN             => '0',           -- 1-bit input: Clock enable input for CARRYINREG
              CECTRL                => '1',                 -- 1-bit input: Clock enable input for OPMODEREG and CARRYINSELREG
              CED                   => '0',                       -- 1-bit input: Clock enable input for DREG
              CEINMODE              => '1',             -- 1-bit input: Clock enable input for INMODEREG
              CEM                   => '1',                       -- 1-bit input: Clock enable input for MREG
              CEP                   => '1',                       -- 1-bit input: Clock enable input for PREG
              RSTA                  => rst,                     -- 1-bit input: Reset input for AREG
              RSTALLCARRYIN         => rst,   -- 1-bit input: Reset input for CARRYINREG
              RSTALUMODE            => rst,         -- 1-bit input: Reset input for ALUMODEREG
              RSTB                  => rst,                     -- 1-bit input: Reset input for BREG
              RSTC                  => rst,                     -- 1-bit input: Reset input for CREG
              RSTCTRL               => rst,               -- 1-bit input: Reset input for OPMODEREG and CARRYINSELREG
              RSTD                  => rst,                     -- 1-bit input: Reset input for DREG and ADREG
              RSTINMODE             => rst,           -- 1-bit input: Reset input for INMODEREG
              RSTM                  => rst,                     -- 1-bit input: Reset input for MREG
              RSTP                  => rst                      -- 1-bit input: Reset input for PREG
           );
        end generate;
    end generate;

        p_adder: process(clk)
        begin
            if rising_edge(clk) then
                if rst = '1' then
                   mult_res_val <= (others => '0');
                   mult_res_last <= (others => '0');
                   mult_res_user <= (others => '0');
                   data_out_val <= '0';
                   data_out_last <= '0';
                   first_data <= '1';
                else
                    if first_data = '1' and data_in_val = '1' then
                        mult_res_user(0) <= data_in_user;
                        first_data <= '0';
                    else
                        mult_res_user(0) <= '0';
                    end if;
                    if data_in_last = '1' and data_in_val = '1' then
                        first_data <= '1';
                    end if;
                    mult_res_val(0) <= data_in_val;
                    mult_res_last(0) <= data_in_last;
                    mult_res_val(1) <= mult_res_val(0);
                    mult_res_last(1) <= mult_res_last(0);
                    mult_res_user(1) <= mult_res_user(0);

                    data_out_val <= mult_res_val(1);
                    data_out_last <= mult_res_last(1);

                    data_out_user <= mult_res_user(1);
                end if;
            end if;
        end process p_adder;

    gen_res_add: for i in 0 to 2 generate
        p_adder_stage: process(clk)
            type add_stage_t is array(0 to 1) of signed(13 downto 0);
            variable add_stage_1        : add_stage_t;
            variable add_stage_final    : signed(13 downto 0);
            variable add_final          : unsigned(8 downto 0);
        begin
            if rising_edge(clk) then
                if rst = '1' then
                   scale_res(i) <= (others => '0'); 
                else

                    if TAP_NUM = 6 then
                        --multiplier output is 48 bits, inputs are 27(signed) and 18 bit(unsigned) -> 27+18=45; but we use one bit less, thus we are interested in 43 downto 0 part of the result)
                        --we will take some extra bits for mid results, so we reduce rouding errors
                        --in theory we should not have bit growth at final result, but due to rounding we can have it
                        add_stage_1(0) := resize(signed(mult_res(i)(0)(47 downto 42-10)),14) + resize(signed(mult_res(i)(1)(47 downto 42-10)),14) + resize(signed(mult_res(i)(2)(47 downto 42-10)),14);
                        add_stage_1(1) := resize(signed(mult_res(i)(3)(47 downto 42-10)),14) + resize(signed(mult_res(i)(4)(47 downto 42-10)),14) + resize(signed(mult_res(i)(5)(47 downto 42-10)),14);
                        
                    elsif TAP_NUM = 8 then
                        --multiplier output is 48 bits, inputs are 27(signed) and 18 bit(unsigned) -> 27+18=45; but we use one bit less, thus we are interested in 43 downto 0 part of the result)
                        --we will take some extra bits for mid results, so we reduce rouding errors
                        --in theory we should not have bit growth at final result, but due to rounding we can have it
                        add_stage_1(0) := resize(signed(mult_res(i)(0)(47 downto 42-10)),14) + resize(signed(mult_res(i)(1)(47 downto 42-10)),14) + resize(signed(mult_res(i)(2)(47 downto 42-10)),14) + resize(signed(mult_res(i)(3)(47 downto 42-10)),14);
                        add_stage_1(1) := resize(signed(mult_res(i)(4)(47 downto 42-10)),14) + resize(signed(mult_res(i)(5)(47 downto 42-10)),14) + resize(signed(mult_res(i)(6)(47 downto 42-10)),14) + resize(signed(mult_res(i)(7)(47 downto 42-10)),14);

                    end if;

                    add_stage_final := add_stage_1(0) + add_stage_1(1);
                    if add_stage_final(add_stage_final'left) = '1' then
                        scale_res(i) <= (others => '0');
                    else
                        add_final := resize(unsigned(add_stage_final(9 downto 2)), add_final'length) + resize(unsigned(add_stage_final(1 downto 1)),9);
                        if (add_stage_final(add_stage_final'left) = '0' and add_stage_final(add_stage_final'left downto add_stage_final'left-3) /= to_signed(0, 4)) or add_final(add_final'left) = '1' then --overflow
                            scale_res(i) <= x"FF"; --maximal value    
                        else
                            scale_res(i) <= std_logic_vector(add_final(7 downto 0));
                        end if;
                    end if;
                end if;
            end if;
        end process p_adder_stage;
    end generate;
    data_out((0+1)*8-1 downto 0*8) <= scale_res(0);
    data_out((1+1)*8-1 downto 1*8) <= scale_res(1);
    data_out((2+1)*8-1 downto 2*8) <= scale_res(2);

end architecture rtl;
