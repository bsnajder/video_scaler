%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Video Scaler IP - FPGA-based Video Scaling Solution
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Copyright (c) 2025 Boris Snajder
% 
% This source describes Open Hardware and is licensed under the CERN-OHL-P v2
% 
% You may redistribute and modify this source and make products using it under
% the terms of the CERN-OHL-P v2 (https://ohwr.org/cern_ohl_p_v2.txt).
% 
% This source is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,
% INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A
% PARTICULAR PURPOSE. Please see the CERN-OHL-P v2 for applicable conditions.
% 
% Source location: https://github.com/bsnajder/video_scaler
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% File: generate_coef_table_vhdl.m
% Description: Octave script to generate VHDL package with coefficient ROM
%              for polyphase interpolation filter.
% Author: Boris Snajder
% Created: 2025
% Modified: 2025-09-20
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function generate_coef_table_vhdl(N_taps, N_phases, data_width, frac_bits, output_filename, package_name)

    % Define x values
    x = [-N_taps/2: 1/N_phases : N_taps/2];
    y = sinc(x);
    window_hann = hann(numel(y));
    y = y(:) .* window_hann(:);

    y = fliplr(y);

    % Normalize to maximum value 1.0 (optional)
    y = y / max(abs(y));

    % Quantize to integer
    max_val = 2^(data_width-1) - 1;  % assuming signed format
    scale_factor = 2^frac_bits;
    y_quantized = round(y * scale_factor);

    % Saturate values to avoid overflow
    y_quantized = min(max(y_quantized, -max_val-1), max_val);


 % Start building VHDL output
    vhdl_lines = {};

    % Package header
    vhdl_lines{end+1} = sprintf('library ieee;');
    vhdl_lines{end+1} = sprintf('use ieee.std_logic_1164.all;');
    vhdl_lines{end+1} = sprintf('use ieee.numeric_std.all;');
    vhdl_lines{end+1} = '';
    vhdl_lines{end+1} = sprintf('package %s is', package_name);
    vhdl_lines{end+1} = '';
    %vhdl_lines{end+1} = sprintf('    constant C_TAP_SIZE       : integer := %d;', N_phases);
    %vhdl_lines{end+1} = sprintf('    constant C_TAP_NUM        : integer := %d;', N_taps);
    %vhdl_lines{end+1} = sprintf('    constant C_TAP_RES        : integer := %d;', 16);
    vhdl_lines{end+1} = '';
    %vhdl_lines{end+1} = '    type coef_rom_arr_t is array (0 to C_TAP_SIZE-1) of signed(C_TAP_RES-1 downto 0);';
    vhdl_lines{end+1} = sprintf('    type coef_rom_arr_t is array (0 to %d) of signed(15 downto 0);', N_phases-1);
    vhdl_lines{end+1} = sprintf('    type coef_rom_%d_t is array (0 to %d) of coef_rom_arr_t;', N_taps, N_taps-1);
    %vhdl_lines{end+1} = '    type coef_rom_out_t is array (C_TAP_NUM-1 downto 0) of std_logic_vector(C_TAP_RES-1 downto 0);';
    vhdl_lines{end+1} = '';

    % Generate each ROM_TAP_X constant
    for tap_idx = 0:1:N_taps-1
        %vhdl_lines{end+1} = sprintf('    constant ROM_TAP_%d_%d : coef_rom_arr_t := (', N_taps, tap_idx);
        vhdl_lines{end+1} = sprintf('    constant ROM_TAP_%d_%d : coef_rom_arr_t := (', N_taps, N_taps-tap_idx-1);

        line = '        ';
        for phase_idx = 1:N_phases
            val = y_quantized(tap_idx*N_phases+phase_idx);%:tap_idx+N_phases);

            % Proper signed hex formatting
            val_hex = dec2hex(bitand(int64(val), 2^data_width-1), ceil(data_width/4));

            line = [line, sprintf('X"%s"', upper(val_hex))];

            if phase_idx ~= N_phases
                line = [line, ', '];
            end

            if mod(phase_idx, 8) == 0 && phase_idx ~= N_phases
                vhdl_lines{end+1} = line;
                line = '        ';
            end
        end
        if ~isempty(strtrim(line))
            vhdl_lines{end+1} = line;
        end
        vhdl_lines{end+1} = '    );';
        vhdl_lines{end+1} = '';
    end

    % Generate the TAP_COEF_ROM
    vhdl_lines{end+1} = sprintf('    constant TAP_%d_COEF_ROM : coef_rom_%d_t := (', N_taps, N_taps);
    line = '        ';
    for tap_idx = 0:N_taps-1
        line = [line, sprintf('ROM_TAP_%d_%d', N_taps, tap_idx)];
        if tap_idx ~= N_taps-1
            line = [line, ', '];
        end
        %if mod(tap_idx+1, 4) == 0 && tap_idx ~= N_taps-1
            vhdl_lines{end+1} = line;
            line = '        ';
        %end
    end
    if ~isempty(strtrim(line))
        vhdl_lines{end+1} = line;
    end
    vhdl_lines{end+1} = '    );';
    vhdl_lines{end+1} = '';

    % Package end
    vhdl_lines{end+1} = sprintf('end package %s;', package_name);

    % Write to file
    fid = fopen(output_filename, 'w');
    for k = 1:numel(vhdl_lines)
        fprintf(fid, '%s\n', vhdl_lines{k});
    end
    fclose(fid);

    fprintf('VHDL package written to %s\n', output_filename);
end
