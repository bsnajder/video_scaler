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
% File: write_array_to_csv.m
% Description: Utility function to write a 3D array to CSV file format.
% Author: Boris Snajder
% Created: 2025
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function write_array_to_csv(array, filename)
    % array: 3D numeric array (height x width x color channels)
    % filename: output CSV file name (e.g., 'output.csv')

    % Open the file
    fid = fopen(filename, 'w');
    if fid == -1
        error('Cannot open file: %s', filename);
    end

    % Write each row
    [rows, cols, color] = size(array);
    for r = 1:rows
        for c = 1:cols
            if c == cols
                fprintf(fid, '%g, %g, %g', array(r,c, 1), array(r,c, 2), array(r,c, 3));  % no comma at end of line
            else
                fprintf(fid, '%g, %g, %g, ', array(r,c,1), array(r,c,2), array(r,c,3)); % comma between numbers
            end
        end
        fprintf(fid, '\n'); % new line after each row
    end

    fclose(fid);
    fprintf('Array written to %s\n', filename);
end
