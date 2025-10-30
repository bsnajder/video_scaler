-------------------------------------------------------------------------------
--                              LIBRARIES
-------------------------------------------------------------------------------
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
-- File: fifo_fwft.vhd
-- Description: First Word Fall Through (FWFT) FIFO implementation for buffering
--              video data in the scaler pipeline. Provides configurable depth
--              and almost-full watermark with standard FIFO interface.
-- Author: Boris Snajder
-- Created: 2025
-- Modified: 2025-09-20
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library utils;
use utils.utils_pkg.all;


entity fifo_fwft is
    generic(
        DWIDTH          : positive; -- data width
        DEPTH           : positive; -- has to be a power of 2
        WR_AFULL_WM     : positive  -- almost full watermark
    );
    port (
        --
        clk         : in std_logic;
        rst         : in std_logic;
        --
        wr_en       : in std_logic;
        wr_data     : in std_logic_vector(DWIDTH-1 downto 0);
        wr_afull    : out std_logic;
        wr_full     : out std_logic;
        --
        rd_en       : in std_logic;
        rd_data     : out std_logic_vector(DWIDTH-1 downto 0);
        rd_valid    : out std_logic
    );
end fifo_fwft;

architecture rtl of fifo_fwft is

    signal wr_ptr       : unsigned(LOG2(DEPTH) downto 0) := (others => '0');
    signal rd_ptr       : unsigned(LOG2(DEPTH) downto 0) := (others => '0');

    signal wr_full_i    : std_logic := '0';
    signal wr_afull_i   : std_logic := '0';
    signal rd_empty_i   : std_logic := '1';
    
    signal wr_data_i    : std_logic_vector(DWIDTH-1 downto 0);
    signal rd_data_i    : std_logic_vector(DWIDTH-1 downto 0) := (others => '0');
    signal mem_data_out : std_logic_vector(DWIDTH-1 downto 0);
    
    signal wr_en_int    : std_logic;
    
    signal rd_en_int    : std_logic := '0';
    signal first_read   : std_logic;
    signal read_empty_int: std_logic;

begin
    -- Write pointer
    process (clk)
    begin
        if rising_edge(clk) then
            if (rst = '1') then
                wr_ptr <= (others => '0');
            else
                if (wr_en_int = '1') then
                    wr_ptr <= wr_ptr + 1;
                end if;
            end if;
        end if;
    end process;  

    -- Read pointer
    process (clk)
    begin
        if rising_edge(clk) then
            if (rst = '1') then
                rd_ptr <= (others => '0');
            else
                if (rd_en_int = '1') then
                    rd_ptr <= rd_ptr + 1;
                end if;
            end if;
        end if;
    end process;    

    process (clk)
        variable curr_status     : unsigned(LOG2(DEPTH) downto 0);
        variable curr_wr_full_v     : std_logic;
    begin
        if rising_edge(clk) then
            if (rst = '1') then
                wr_full_i <= '0';
                wr_afull_i <= '0';
                rd_empty_i <= '1';
            else
                curr_status(curr_status'left-1 downto 0) := wr_ptr(wr_ptr'left-1 downto 0) - rd_ptr(rd_ptr'left-1 downto 0);
                if curr_status(curr_status'left-1 downto 0) = 0 and wr_ptr(wr_ptr'left) /= rd_ptr(rd_ptr'left) then
                    curr_status(curr_status'left) := '1';
                else
                    curr_status(curr_status'left) := '0';
                end if;   
                
                if (wr_en_int = '1' and rd_en_int = '0') then
                    curr_status := curr_status + 1;
                elsif (wr_en_int = '0' and rd_en_int = '1') then
                    curr_status := curr_status - 1;
                end if;
                
                if (curr_status = DEPTH) then
                    wr_full_i <= '1';
                else
                    wr_full_i <= '0';
                end if;

                if curr_status >= WR_AFULL_WM then
                    wr_afull_i <= '1';
                else
                    wr_afull_i <= '0';
                end if;      

                if (curr_status = 0) then
                    rd_empty_i <= '1';
                else
                    rd_empty_i <= '0';
                end if;

            end if;
        end if;
    end process;
 

    wr_full     <= wr_full_i;  
    wr_afull    <= wr_afull_i;  
    
    process (clk)
    begin
        if rising_edge(clk) then
            if (rd_en_int = '0' and read_empty_int = '1') then 
                first_read <= '1';
            end if;
            if rd_en_int = '1' then
                first_read <= '0';
            end if;
        end if;
    end process;
    
    rd_en_int <= (rd_en or first_read) and (not rd_empty_i);
    
    process (clk)
    begin
        if rising_edge(clk) then
            if (rst = '1') then
                read_empty_int <= '1';
            else
                --we are going to place data on the bus -> assert valid signal
                if (rd_en_int = '1') then
                    read_empty_int <= '0';
                end if;
                
                -- there is valid data on the bus, that has been acked by slave, but we did not popped new data
                if (read_empty_int = '0' and rd_en = '1' and rd_en_int = '0') then 
                    read_empty_int <= '1';
                end if;
            end if;
        end if;
    end process;  
    
    rd_valid <= not read_empty_int;

    process (clk)
    begin
        if rising_edge(clk) then
            if (rst = '1') then
                rd_data <= (others => '0');
            else
                if (rd_en_int = '1') then
                    rd_data <= rd_data_i;
                end if;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- MEMORY
    -----------------------------------------------------------------------
    wr_en_int <= wr_en and not(wr_full_i); -- do not overwrite data in FIFO if FIFO is full
    
    u_mem: entity utils.dp_lutram(rtl)
    generic map (
        DWIDTH => DWIDTH,
        DEPTH  => DEPTH
    )
    port map (
        clk     => clk,
        we      => wr_en_int,
        wr_addr => std_logic_vector(wr_ptr(wr_ptr'left-1 downto 0)), 
        rd_addr => std_logic_vector(rd_ptr(rd_ptr'left-1 downto 0)), 
        din     => wr_data,
        dout    => rd_data_i
    );
       
end rtl;
