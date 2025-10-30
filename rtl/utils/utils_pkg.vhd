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
-- File: utils_pkg.vhd
-- Description: Utility package containing common functions and constants for
--              the video scaler IP. 
-- Author: Boris Snajder
-- Created: 2025
-- Modified: 2025-09-20
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;

-------------------------------------------------------------------------------
-- 								     PACKAGE
-------------------------------------------------------------------------------
package utils_pkg is
    ---------------------------------------------------
    -- LOG2
    ---------------------------------------------------
    -- Base 2 logarithm function.
    ---------------------------------------------------
    -- Parameters:
    --  * func_in: logarithm parameter,
    --         non negative integer
    ---------------------------------------------------
    -- Returns:
    --  * Integer part of a base two logarithm
    --    for a given non-negative integer parameter.
    --    Based on 32 bit integer implementation the
    --    Value of LOG2 is between 0 and 31.
    --    If func_in is not a power of two the LOG2
    --    will return the value for the next greater
    --    power of two.
    --    The function will return -1 if no adequate
    --    number is found.	
    ---------------------------------------------------
    function LOG2(func_in : natural) return integer;
    
    ---------------------------------------------------
    -- MAX 
    ---------------------------------------------------
    -- Returns the maximum of two integer values.
    ---------------------------------------------------
    -- Parameters:
    --  * num1: First integer value to compare
    --  * num2: Second integer value to compare
    ---------------------------------------------------
    -- Returns:
    --  * Integer value representing the maximum of 
    --    num1 and num2
    ---------------------------------------------------
    function MAX(num1: integer; num2: integer) return integer;     
    
    ---------------------------------------------------
    -- MIN 
    ---------------------------------------------------
    -- Returns the minimum of two integer values.
    ---------------------------------------------------
    -- Parameters:
    --  * num1: First integer value to compare
    --  * num2: Second integer value to compare
    ---------------------------------------------------
    -- Returns:
    --  * Integer value representing the minimum of 
    --    num1 and num2
    ---------------------------------------------------
    function MIN(num1: integer; num2: integer) return integer;       
    
    ---------------------------------------------------
    -- VEC_LO
    ---------------------------------------------------
    -- Creates a std_logic_vector with all bits set to '0'.
    ---------------------------------------------------
    -- Parameters:
    --  * vec_size: Size of the vector to create (positive)
    ---------------------------------------------------
    -- Returns:
    --  * std_logic_vector of specified size with all
    --    bits initialized to '0'
    ---------------------------------------------------
    function VEC_LO(vec_size: positive) return std_logic_vector;

    ---------------------------------------------------
    -- UVEC_LO
    ---------------------------------------------------
    -- Creates an unsigned vector with all bits set to '0'.
    ---------------------------------------------------
    -- Parameters:
    --  * vec_size: Size of the vector to create (positive)
    ---------------------------------------------------
    -- Returns:
    --  * unsigned vector of specified size with all
    --    bits initialized to '0'
    ---------------------------------------------------
    function UVEC_LO(vec_size: positive) return unsigned;
    
    ---------------------------------------------------
    -- VEC_HI
    ---------------------------------------------------
    -- Creates a std_logic_vector with all bits set to '1'.
    ---------------------------------------------------
    -- Parameters:
    --  * vec_size: Size of the vector to create (positive)
    ---------------------------------------------------
    -- Returns:
    --  * std_logic_vector of specified size with all
    --    bits initialized to '1'
    ---------------------------------------------------
    function VEC_HI(vec_size: positive) return std_logic_vector;

    ---------------------------------------------------
    -- UVEC_HI
    ---------------------------------------------------
    -- Creates an unsigned vector with all bits set to '1'.
    ---------------------------------------------------
    -- Parameters:
    --  * vec_size: Size of the vector to create (positive)
    ---------------------------------------------------
    -- Returns:
    --  * unsigned vector of specified size with all
    --    bits initialized to '1'
    ---------------------------------------------------
    function UVEC_HI(vec_size: positive) return unsigned;
    

    ---------------------------------------------------
    -- RESOLVE
    ---------------------------------------------------
    -- Resolves a std_logic signal to '0' or '1'.
    ---------------------------------------------------
    -- Parameters:
    --  * s: Input std_logic signal to resolve
    ---------------------------------------------------
    -- Returns:
    --  * std_logic value: '1' if input is '1',
    --    '0' otherwise (handles 'U', 'X', 'Z', etc.)
    ---------------------------------------------------
    function RESOLVE(s : std_logic) return std_logic;    

    ---------------------------------------------------
    -- RESOLVE
    ---------------------------------------------------
    -- Resolves a std_logic_vector to contain only '0' and '1'.
    ---------------------------------------------------
    -- Parameters:
    --  * s: Input std_logic_vector to resolve
    ---------------------------------------------------
    -- Returns:
    --  * std_logic_vector with each bit resolved to
    --    '1' if original bit is '1', '0' otherwise
    --    (handles 'U', 'X', 'Z', etc. states)
    ---------------------------------------------------
    function RESOLVE(s : std_logic_vector) return std_logic_vector;

    ---------------------------------------------------
    -- RESOLVE_STDV
    ---------------------------------------------------
    -- Alternative std_logic_vector resolution function.
    ---------------------------------------------------
    -- Parameters:
    --  * s: Input std_logic_vector to resolve
    ---------------------------------------------------
    -- Returns:
    --  * std_logic_vector with each bit resolved to
    --    '1' if original bit is '1', '0' otherwise
    --    (identical functionality to RESOLVE)
    ---------------------------------------------------
    function RESOLVE_STDV(s : std_logic_vector) return std_logic_vector;
    
    ---------------------------------------------------
    -- ITE (If-Then-Else)
    ---------------------------------------------------
    -- Conditional selection function for integers.
    ---------------------------------------------------
    -- Parameters:
    --  * cond: Boolean condition to evaluate
    --  * in1: Value returned if condition is true
    --  * in2: Value returned if condition is false
    ---------------------------------------------------
    -- Returns:
    --  * in1 if cond is true, in2 if cond is false
    ---------------------------------------------------
    function ITE(cond: boolean; in1: integer; in2: integer) return integer;
    
    ---------------------------------------------------
    -- ITE (If-Then-Else)
    ---------------------------------------------------
    -- Conditional selection function for std_logic.
    ---------------------------------------------------
    -- Parameters:
    --  * cond: Boolean condition to evaluate
    --  * in1: Value returned if condition is true
    --  * in2: Value returned if condition is false
    ---------------------------------------------------
    -- Returns:
    --  * in1 if cond is true, in2 if cond is false
    ---------------------------------------------------
    function ITE(cond: boolean; in1: std_logic; in2: std_logic) return std_logic;

end utils_pkg;

-------------------------------------------------------------------------------
--                         PACKAGE BODY
-------------------------------------------------------------------------------
package body utils_pkg is
    ---------------------------------------------------
    -- LOG2
    ---------------------------------------------------
    -- Base 2 logarithm function implementation.
    ---------------------------------------------------	
    function LOG2(func_in : natural) return integer is
    begin
        for i in 0 to 31 loop
            if (2**i >= func_in) then
                return i;
            end if;
        end loop;
        return -1;
    end LOG2;
        
    ---------------------------------------------------
    -- MAX 
    ---------------------------------------------------
    -- Returns the maximum of two integer values.
    ---------------------------------------------------
    function MAX(num1: integer; num2: integer) return integer is
    begin
        if num1>num2 then
            return num1;
        else
            return num2;
        end if;
    end MAX;        

    ---------------------------------------------------
    -- MIN 
    ---------------------------------------------------
    -- Returns the minimum of two integer values.
    ---------------------------------------------------
    function MIN(num1: integer; num2: integer) return integer is
    begin
        if num1<num2 then
            return num1;
        else
            return num2;
        end if;
    end MIN;           

    ---------------------------------------------------
    -- VEC_LO
    ---------------------------------------------------
    -- Creates a std_logic_vector with all bits set to '0'.
    ---------------------------------------------------
    function VEC_LO(vec_size: positive) return std_logic_vector is
        variable ret_vec : std_logic_vector(vec_size -1 downto 0);
    begin    
        ret_vec(vec_size-1 downto 0) := (others => '0');
        return ret_vec;
    end VEC_LO;
        
    ---------------------------------------------------
    -- UVEC_LO
    ---------------------------------------------------
    -- Creates an unsigned vector with all bits set to '0'.
    ---------------------------------------------------
    function UVEC_LO(vec_size: positive) return unsigned is
        variable ret_vec : unsigned(vec_size -1 downto 0);
    begin    
        ret_vec(vec_size-1 downto 0) := (others => '0');
        return ret_vec;
    end UVEC_LO;
    
    ---------------------------------------------------
    -- VEC_HI
    ---------------------------------------------------
    -- Creates a std_logic_vector with all bits set to '1'.
    ---------------------------------------------------
    function VEC_HI(vec_size: positive) return std_logic_vector is
        variable ret_vec : std_logic_vector(vec_size -1 downto 0);
    begin    
        ret_vec(vec_size-1 downto 0) := (others => '1');
        return ret_vec;
    end VEC_HI;    
    
    ---------------------------------------------------
    -- UVEC_HI
    ---------------------------------------------------
    -- Creates an unsigned vector with all bits set to '1'.
    ---------------------------------------------------
    function UVEC_HI(vec_size: positive) return unsigned is
        variable ret_vec : unsigned(vec_size -1 downto 0);
    begin    
        ret_vec(vec_size-1 downto 0) := (others => '1');
        return ret_vec;
    end UVEC_HI;


    ---------------------------------------------------
    -- RESOLVE
    ---------------------------------------------------
    -- Resolves a std_logic signal to binary values only.
    -- Converts any metavalue ('U', 'X', 'Z', etc.) to '0'.
    ---------------------------------------------------
    function RESOLVE(s : std_logic) return std_logic is
        variable result : std_logic;
    begin

        if s = '1' then
            result := '1';
        else
            result := '0';  -- All non-'1' values become '0'
        end if;

        return result;
    end RESOLVE;

    ---------------------------------------------------
    -- RESOLVE
    ---------------------------------------------------
    -- Resolves a std_logic_vector to binary values only.
    -- Converts any metavalue ('U', 'X', 'Z', etc.) to '0'.
    ---------------------------------------------------
    function RESOLVE(s : std_logic_vector) return std_logic_vector is
        variable result : std_logic_vector(s'range);
    begin
        for i in s'range loop
            if s(i) = '1' then
                result(i) := '1';
            else
                result(i) := '0';  -- All non-'1' values become '0'
            end if;
        end loop;
        return result;
    end RESOLVE;

    ---------------------------------------------------
    -- RESOLVE_STDV
    ---------------------------------------------------
    -- Alternative std_logic_vector resolution function.
    -- Identical functionality to RESOLVE function.
    ---------------------------------------------------
    function RESOLVE_STDV(s : std_logic_vector) return std_logic_vector is
        variable result : std_logic_vector(s'range);
    begin
        for i in s'range loop
            if s(i) = '1' then
                result(i) := '1';
            else
                result(i) := '0';  -- All non-'1' values become '0'
            end if;
        end loop;
        return result;
    end RESOLVE_STDV;    

        
    ---------------------------------------------------
    -- ITE (If-Then-Else)
    ---------------------------------------------------
    -- Conditional selection function for integers.
    -- Provides ternary operator functionality.
    ---------------------------------------------------
    function ITE(cond: boolean; in1: integer; in2: integer) return integer is
        variable result: integer;
    begin
        result := in2;  -- Default to false condition value
        if cond = true then
            result := in1;  -- Override with true condition value
        end if;
        return result;
    end ITE;

    ---------------------------------------------------
    -- ITE (If-Then-Else)
    ---------------------------------------------------
    -- Conditional selection function for std_logic.
    -- Provides ternary operator functionality.
    ---------------------------------------------------
    function ITE(cond: boolean; in1: std_logic; in2: std_logic) return std_logic is
        variable result: std_logic;
    begin
        result := in2;  -- Default to false condition value
        if cond = true then
            result := in1;  -- Override with true condition value
        end if;
        return result;
    end ITE;

end utils_pkg;
