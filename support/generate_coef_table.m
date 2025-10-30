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
% File: generate_coef_table.m
% Description: Function to generate coefficient tables for polyphase filters.
% Author: Boris Snajder
% Created: 2025
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function coefs = generate_coef_table(N_taps, N_phases, data_width, frac_bits)

    % Define x values, avoiding division by zero
    %x = [-N_taps/2: 1/(N_phases) : N_taps/2-1/N_phases];
    x = [-N_taps/2: 1/(N_phases) : N_taps/2];
    y = sinc(x);  % sinc(x) in MATLAB is defined as sin(pi*x)/(pi*x)
    window_hann = hann(numel(y));
    y = y(:) .* window_hann(:);

    % Normalize to maximum value 1.0 (optional)
    y = y / max(abs(y));

    % Quantize to integer
    %data_width = 16;
    max_val = 2^(data_width-1) - 1;  % assuming signed format
    scale_factor = 2^frac_bits;
    y = round(y * scale_factor)/scale_factor;
    %y = min(max(y, -max_val-1), max_val);

    if (1)
        % Plot the function
        figure;
        plot(x, y, 'bo-', 'LineWidth', 2);
        grid on;
        xlabel('x');
        ylabel('sin(x)/x');
        title('Sinc Function: sin(x)/x');
        legend('sin(x)/x');
    end
    coefs = y;
end

