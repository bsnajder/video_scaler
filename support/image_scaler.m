%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Video Scaler IP - FPGA-based Video Scaling Solution
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Copyright (c) 2024-2025 Boris Snajder
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
% File: image_scaler.m
% Description: Octave script to test image scaling functionality.
% Author: Boris Snajder
% Created: 2025
% Modified: 2025-09-20
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
pkg load signal
pkg load image

IMG_IN_helper = imread("https://upload.wikimedia.org/wikipedia/commons/9/93/2012_in_Plitvice_Lakes_National_Park_-_j.jpg");
img_in = imresize (IMG_IN_helper, [480 640]);
imshow(img_in)
imwrite(img_in, "in_image.jpg");

write_array_to_csv(img_in(:,:,:), 'in_image.csv');

output_res_x = 1920;
output_res_y = 1080;



scale_x = output_res_x/size(img_in, 2);
scale_y = output_res_y/size(img_in, 1);

step_x = 1/scale_x;
frac_size = 22;
step_x_integer = int64(step_x * 2^frac_size);
step_y = 1/scale_y;
step_y_integer = int64(step_y * 2^frac_size);
if scale_x > 1
    step_x_integer = step_x_integer + 1;
end
if scale_y > 1
    step_y_integer = step_y_integer + 1;
end

N_taps = 8; %it should be even
N_phases = 32; %it should be power of 2

coefs = generate_coef_table(N_taps, N_phases, 16, 14);
if N_taps == 6 && N_phases == 32
    generate_coef_table_vhdl(N_taps, N_phases, 16, 14, 'scale_rom_6_32.vhd', 'coef_6T_32P_pkg');
end
if N_taps == 8 && N_phases == 32
    generate_coef_table_vhdl(N_taps, N_phases, 16, 14, 'scale_rom_8_32.vhd', 'coef_8T_32P_pkg');
end

clear out_line;
%run horizontal scaling
run_hor = 1;
if run_hor == 1
    for h_line = 1:size(img_in, 1)
        current_line(:,:) = img_in(h_line,:,:);
        current_line = squeeze(current_line);
        out_line(h_line ,:,:) = scale_image(current_line, step_x_integer, frac_size, coefs, N_taps, N_phases);
    end
else
    out_line = img_in;
end

clear image_res;
%run vertical scaling
for v_line = 1:size(out_line, 2)
    current_data(:,:) = out_line(:,v_line,:);
    current_data = squeeze(current_data);
    vertical_result = scale_image(current_data, step_y_integer, frac_size, coefs, N_taps, N_phases);
    image_res(:,v_line,:) = vertical_result;
end

imshow(uint8(image_res))

