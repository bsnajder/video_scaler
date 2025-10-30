
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
% File: scale_image.m
% Description: Function to perform image scaling using polyphase interpolation.
% Author: Boris Snajder
% Created: 2025
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function out_vector = scale_image(input_vector, step_integer, frac_size, coefs, N_taps, N_phases)

    frac_one = int64(1) * 2^frac_size;
    frac_curr_position = int64(0);

    %calculate where is 1 of sinx/x in our table;
    %coefs_central_tap_pos = (numel(coefs)-1)/2+1;%+1 is for matlab indexing
    coefs_index_offset = int64([0:N_taps-1]*N_phases+1);%+1 is for matlab indexing
    interpolation_res_vector = zeros(4096, size(input_vector, 2));
    interpolation_res_index = 0;

    for i = 1:size(input_vector,1)
        %while (curr_position < fi_one)
        while(frac_curr_position < frac_one)
            %we need to take fractional part
            %we assume that curr_postion is larger than zero

            frac_pos_fraction = bitand(frac_curr_position, int64(2^frac_size-1));
            %here, we require that N_phases is pow of number 2
            frac_interpolation_phase = bitshift(frac_pos_fraction, -(frac_size-log2(N_phases)));

            %pick up coefs from the table
            coefs_pos = frac_interpolation_phase + coefs_index_offset;

            coefs_run = coefs(coefs_pos);
            coefs_run = flipud(coefs_run);
            %prepare data
            %if N_taps if 4, we calculate interpolation on 4 pixels, we
            %take one pixel from the left (4/2-1), current pixel, and next two
            %pixels (4/2)
            interpolation_data = zeros(N_taps, size(input_vector,2));
            interpolation_data(N_taps/2,:) = input_vector(i,:);

            prior_idx = [i-N_taps/2+1:i-1];
            for help_i = 1:numel(prior_idx)
                    if prior_idx(help_i) <= 0
                        prior_idx(help_i) = -prior_idx(help_i);
                        prior_idx(help_i) = prior_idx(help_i) + 2;
                    end
            end

            interpolation_data(1:N_taps/2-1,:) = input_vector(prior_idx,:);

            post_idx = [i+1:i+N_taps/2];
            for help_i = 1:numel(post_idx)
                    if size(input_vector,1) - post_idx(help_i) + 1 <= 0
                        post_idx(help_i) = 2*size(input_vector,1) - post_idx(help_i);
                    end
            end
            interpolation_data(N_taps/2+1:N_taps,:) = input_vector(post_idx,:);

            interpolation_res_index = interpolation_res_index + 1;
            for color_i = 1:size(input_vector,2)
                    interpolation_res = floor(sum(interpolation_data(:, color_i).*coefs_run(:)));
                    interpolation_res_vector(interpolation_res_index, color_i) = max(min(interpolation_res,255),0);
            end

            frac_curr_position = frac_curr_position + step_integer;

        end

        frac_curr_position = frac_curr_position - frac_one;
    end

    out_vector = interpolation_res_vector(1:interpolation_res_index,:);
end
