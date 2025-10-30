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
-- File: scale_top.vhd
-- Description: Top-level module for video scaler IP. Integrates horizontal and
--              vertical scaling engines with AXI4-Lite register interface for
--              runtime configuration of scaling parameters.
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
use scale_ip.scale_pkg.all;

entity scale_top is
    generic (
        AXI_AWIDTH      : positive := 32;
        AXI_DWIDTH      : positive := 32
    );    
    port (
        aclk           : in std_logic;
        aresetn        : in std_logic;
        -- register interface
        s_axi_awvalid           :   in std_logic;
        s_axi_awready           :   out std_logic;
        s_axi_awaddr            :   in std_logic_vector(AXI_AWIDTH-1 downto 0);
        s_axi_awprot            :   in std_logic_vector(2 downto 0);
        --      	           
        s_axi_wvalid            :   in std_logic;
        s_axi_wready            :   out std_logic;
        s_axi_wdata             :   in std_logic_vector(AXI_DWIDTH-1 downto 0);
        s_axi_wstrb             :   in std_logic_vector(AXI_DWIDTH/8-1 downto 0);
        --      	           
        s_axi_bvalid            :   out std_logic;
        s_axi_bready            :   in std_logic;
        s_axi_bresp             :   out std_logic_vector(1 downto 0);
        --      	           
        s_axi_arvalid           :   in std_logic;
        s_axi_arready           :   out std_logic;
        s_axi_araddr            :   in std_logic_vector(AXI_AWIDTH-1 downto 0);
        s_axi_arprot            :   in std_logic_vector(2 downto 0);    
        --      	           
        s_axi_rvalid            :   out std_logic;
        s_axi_rready            :   in std_logic;
        s_axi_rdata             :   out std_logic_vector(AXI_DWIDTH-1 downto 0);
        s_axi_rresp             :   out std_logic_vector(1 downto 0);
    	--
    	axis_tvalid_s_i         :   in std_logic;
    	axis_tready_s_o         :   out std_logic;
    	axis_tdata_s_i          :   in std_logic_vector(ENG_NUM*8*3-1 downto 0);
    	axis_tlast_s_i          :   in std_logic;
        axis_tstrobe_s_i        :   in std_logic_vector(ENG_NUM*3-1 downto 0);
    	axis_tuser_s_i          :   in std_logic_vector(0 downto 0);
        --
        m_axis_tdata_m_o        :   out std_logic_vector(ENG_NUM*8*3-1 downto 0);
        m_axis_tvalid_m_o       :   out std_logic;
        m_axis_tready_m_i       :   in std_logic;
        m_axis_tlast_m_o        :   out std_logic;
        m_axis_tstrobe_m_o      :   out std_logic_vector(ENG_NUM*3-1 downto 0);
        m_axis_tuser_m_o        :   out std_logic_vector(0 downto 0)

    );
end entity scale_top;

architecture rtl of scale_top is

    signal scale_hor              : std_logic_vector(32-1 downto 0);
    signal scale_ver              : std_logic_vector(32-1 downto 0);
    signal res_ver                : std_logic_vector(16-1 downto 0);

    signal reset                  : std_logic;

    signal h_axis_tvalid_o       : std_logic;
    signal h_axis_tready_o       : std_logic;
    signal h_axis_tdata_o        : std_logic_vector(ENG_NUM*3*8-1 downto 0);
    signal h_axis_tlast_o        : std_logic;
    signal h_axis_tstrobe_o      : std_logic_vector(ENG_NUM*3-1 downto 0);
    signal h_axis_tuser_o        : std_logic_vector(0 downto 0);

    signal v_axis_tvalid_o       : std_logic;
    signal v_axis_tready_o       : std_logic;
    signal v_axis_tdata_o        : std_logic_vector(ENG_NUM*8*3-1 downto 0);
    signal v_axis_tlast_o        : std_logic;
    signal v_axis_tstrobe_o      : std_logic_vector(ENG_NUM*3-1 downto 0);
    signal v_axis_tuser_o        : std_logic_vector(0 downto 0);
    
begin

    reset <= not aresetn;
    
    u_reg: entity scale_ip.scale_reg 
    generic map (
       AXI_AWIDTH     => AXI_AWIDTH,  
       AXI_DWIDTH     => AXI_DWIDTH 
    )    
    port map (
        aclk                   => aclk, 
        aresetn                => aresetn, 
        --
        awvalid                => s_axi_awvalid, 
        awready                => s_axi_awready, 
        awaddr                 => s_axi_awaddr, 
        awprot                 => s_axi_awprot, 
        --
        wvalid                 => s_axi_wvalid, 
        wready                 => s_axi_wready, 
        wdata                  => s_axi_wdata, 
        wstrb                  => s_axi_wstrb, 
        --
        bvalid                 => s_axi_bvalid, 
        bready                 => s_axi_bready, 
        bresp                  => s_axi_bresp, 
        --
        arvalid                => s_axi_arvalid, 
        arready                => s_axi_arready, 
        araddr                 => s_axi_araddr, 
        arprot                 => s_axi_arprot, 
        --
        rvalid                 => s_axi_rvalid, 
        rready                 => s_axi_rready, 
        rdata                  => s_axi_rdata, 
        rresp                  => s_axi_rresp, 
        --
        irq                   => open,
        --
        scale_hor              => scale_hor, 
        scale_ver              => scale_ver,
        res_ver                => res_ver
    );
    
    u_scale_hor: entity scale_ip.scale_fsm_hor 
    port map ( 
	    clk                 => aclk, 
	    rst                 => reset, 
        --
        hor_scale           => scale_hor,
    	--
    	axis_tvalid         => axis_tvalid_s_i, 
    	axis_tready         => axis_tready_s_o,
    	axis_tdata          => axis_tdata_s_i,
    	axis_tlast          => axis_tlast_s_i,
        axis_tstrobe        => axis_tstrobe_s_i,
    	axis_tuser          => axis_tuser_s_i,
	    --
        m_axis_tdata        => h_axis_tdata_o,
        m_axis_tvalid       => h_axis_tvalid_o,
        m_axis_tready       => h_axis_tready_o,
        m_axis_tlast        => h_axis_tlast_o,
        m_axis_tstrobe      => h_axis_tstrobe_o,
        m_axis_tuser        => h_axis_tuser_o
    );

    u_scale_vert: entity scale_ip.scale_fsm_vert
    port map ( 
	    clk                 => aclk,
	    rst                 => reset,
        --
        vert_res            => res_ver,
        vert_scale          => scale_ver,
    	--
    	axis_tvalid_s_i     => h_axis_tvalid_o,
    	axis_tready_s_o     => h_axis_tready_o,
    	axis_tdata_s_i      => h_axis_tdata_o,
    	axis_tlast_s_i      => h_axis_tlast_o,
        axis_tstrobe_s_i    => h_axis_tstrobe_o,
    	axis_tuser_s_i      => h_axis_tuser_o,
	    --
        m_axis_tdata_m_o    => v_axis_tdata_o,
        m_axis_tvalid_m_o   => v_axis_tvalid_o,
        m_axis_tready_m_i   => v_axis_tready_o,
        m_axis_tlast_m_o    => v_axis_tlast_o,
        m_axis_tstrobe_m_o  => v_axis_tstrobe_o,
        m_axis_tuser_m_o    => v_axis_tuser_o
    );

    m_axis_tdata_m_o    <= v_axis_tdata_o;
    m_axis_tvalid_m_o   <= v_axis_tvalid_o;
    m_axis_tlast_m_o    <= v_axis_tlast_o;
    m_axis_tstrobe_m_o  <= v_axis_tstrobe_o;
    m_axis_tuser_m_o    <= v_axis_tuser_o;
    v_axis_tready_o     <= m_axis_tready_m_i;

end architecture rtl;
