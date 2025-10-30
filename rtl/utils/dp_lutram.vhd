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
-- File: dp_lutram.vhd
-- Description: Dual-port LUT RAM implementation for small memory blocks.
-- Author: Boris Snajder
-- Created: 2025
-- Modified: 2025-09-20
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library utils;
use utils.utils_pkg.all;

entity dp_lutram is
    generic (
        DWIDTH : positive := 8;
        DEPTH  : positive := 32
    );
    port (
        clk     : in std_logic;
        we      : in std_logic;
        wr_addr : in std_logic_vector(log2(DEPTH)-1 downto 0);
        rd_addr : in std_logic_vector(log2(DEPTH)-1 downto 0);
        din     : in std_logic_vector(DWIDTH-1 downto 0);
        dout    : out std_logic_vector(DWIDTH-1 downto 0)
    );
end entity;

architecture rtl of dp_lutram is

    type ram_type is array (0 to DEPTH-1) of std_logic_vector(DWIDTH-1 downto 0);
    signal ram : ram_type;

begin

    -- Write port
    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                ram(to_integer(unsigned(wr_addr))) <= din;
            end if;
        end if;
    end process;

    -- Read port
    dout <= ram(to_integer(unsigned(rd_addr)));

end architecture;