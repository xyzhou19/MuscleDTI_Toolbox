function [final_fibers, final_curvature, final_angle, final_distance, qual_mask, num_tracked, mean_fiber_props, mean_apo_props] = ...
    fiber_goodness(fiber_all, angle_list, distance_list, curvature_list, n_points, roi_flag, apo_area, roi_mesh, fg_options)
%
%FUNCTION fiber_goodness
%  [final_fibers, final_curvature, final_angle, final_distance, qual_mask, num_tracked, mean_fiber_props, mean_apo_props] = ...
%     fiber_goodness(smoothed_fiber_all, angle_list, distance_list, curvature_list, n_points, roi_flag, apo_area, roi_mesh, fg_options);
%
%USAGE
%  The function fiber_goodness is used to assess the goodness of fiber tract  
%  data, and reject outlying fiber tract data, in the MuscleDTI_Toolbox. An 
%  optional, second-stage selection process allow the user to uniformaly 
%  sample the aponeurosis mesh.
%  
%  The quality algorithm described in Heemskerk et al, 2008 is implemented, 
%  but updated to account for the inclusion of curvature in the architectural
%  computations. Specifically, the fibers are selected for having:
%    1) Monotonically increasing values in the Z direction. In fiber_track, the  
%       Z component of the first eigenvector is forced to be positive; so the  
%       Z components of the unfitted tracts must increase monotonically.   
%       However, negative steps in the Z direction could result from overfitting   
%       fiber tract smoothing process. Fiber tracts with monotonically increasing 
%       Z values are indicated by entering a value of 1 at the corresponding  
%       [row column] indices in the 1st level of the 3rd dimension of qual_mask.  
%       The number of tracts that meet this criterion are calculated and added
%       to the 1st index of the vector num_tracked. Tracts that meet this 
%       criterion are advanced to the next level of selection.
%    2) 2.	A minimum length, in mm.  This is specified by the user as a field 
%       in the structure fs_options. Fiber tracts that meet this criterion are 
%       indicated by entering a value of 1 at the corresponding [row column] 
%       indices in the 2nd level of the 3rd dimension of qual_mask. The total 
%       number of tracts that meet this criterion are calculated and added to 
%       the 2nd index into the vector num_tracked. Tracts that meet this 
%       criterion are advanced to the next level of selection;
%    3) An acceptable pennation angle, in degrees.  This range is defined 
%       by the user in the structure fs_options. Fiber tracts that meet this 
%       criterion are indicated by entering a value of 1 at the corresponding 
%       [row column] indices in the 3rd level of the 3rd dimension of qual_mask. 
%       The total number of tracts that meet this criterion are calculated and 
%       added to the 3rd index into the vector num_tracked. Tracts that meet 
%       this criterion are advanced to the next level of selection.
%    4. An acceptable curvature value, in m-1.  This range is defined by the 
%       user in the structure fs_options. Fiber tracts that meet this criterion 
%       are indicated by entering a value of 1 at the corresponding [row column] 
%       indices in the 4th level of the 3rd dimension of qual_mask. The total 
%       number of tracts that meet this criterion are calculated and added to 
%       the 4th index into the vector num_tracked. Tracts that meet this 
%       criterion are advanced to the next level of selection.
%    5. A length, pennation angle, and curvature that lies within the 95% 
%       confidence interval for length, pennation angle, and curvature set 
%       by the surrounding 24 tracts. Fiber tracts that meet this criterion 
%       are indicated by entering a value of 1 at the corresponding [row column] 
%       indices in the 5th level of the 3rd dimension of qual_mask. The total 
%       number of tracts that meet this criterion are calculated and added to 
%       the 5th index into the vector num_tracked. Tracts that meet this 
%       criterion are advanced to the next step of analysis. 
% The use of length, pennation, and curvature criteria require the user to use 
% their knowledge of the expected patterns of muscle geometry to supply values 
% that are reasonable but will not inappropriately bias the results. These 
% selection criteria, as well as the number of tracts that were rejected 
% because of these criteria, should be included in the Methods sections of 
% publications
%
% An optional final of the selection process is to sample fiber tracts across 
% the aponeurosis at a uniform spatial frequency. Because the aponeurosis 
% changes in width over the superior-inferior direction, the distance between 
% seed points in the roi_mesh matrix varies. This would bias a simple average 
% of the whole-muscle architectural properties toward narrower regions of the 
% aponeurosis, where the seed points occur at higher sampling frequency.
% 
% To avoid this problem, the user may include a field called sampling_frequency
% in the fs_options structure; if present, this produces an approximately 
% uniform spatial sampling of the fiber tracts. To do so, fiber_selector first 
% identifies all tracts that fall within the boundaries of each sampling 
% interval. Then, the median values for length, pennation angle, and curvature
% are calculated. For each tract, a similarity index S is calculated that 
% compares the length, mean pennation angle, and mean curvature of the Tth 
% tract and the local median. The tract with the minimum value of S is taken 
% as the most typical tract in the sampling interval and is used in further steps. 
% If sampling_frequency is not included in fs_options, then this sampling does 
% not occur and the tracts defined in step 5 are used in further steps.
% 
% In either case, the preserved fiber tracts are stored in the matrix 
% final_fibers; their structural properties are stored in the matrices 
% final_curvature, final_angle, and final_distance; and the whole-muscle mean 
% values for length, pennation angle, and curvature are stored in the matrix 
% mean_apo_props.
%
%INPUT ARGUMENTS
% fiber_all: The fiber tracts from which selection will be made.  
%   The matrix could be the output of fiber_track or the smoothed fiber 
%   tracts output from fiber_smoother.
%
% angle_list, distance_list, curvature_list, n_points, apo_area: The outputs 
%   of fiber_quantifier.
%
% roi_flag: A mask indicating fiber tracts that propagated at least one point, 
%   output from fiber_track;
%
% roi_mesh: the output of define_roi 
%
% fg_options: a structure containing the following fields:
%    .dwi_res: a three-element vector containing the field of view, matrix
%        size, and slice thickness of the diffusion-weighted images
%    .min_distance: minimum distance for selected tracts, in mm
%    .min_pennation: minimum pennation angle, in degrees
%    .max_pennation: maximum pennation angle, in degrees
%    .max_curvature: maximum curvature, in m^-1
%    .sampling_frequency (optional): The spatial frequency for uniform
%      sampling of the aponeurosis mesh, in mm^-1
%
%OUTPUT ARGUMENTS
%  final_fibers: the fiber tracts that passed all selection criteria
%
%  final_curvature: pointwise measurements of curvature for the final tracts.
%
%  final_angle: pointwise measurements of pennation angle for the final
%    tracts.
%
%  final_distance: pointwise measurements of cumulative distance for the
%    final tracts
%
%  qual_mask: a 3D matrix of the same row x column size as the roi_mesh, with 6
%    layers corresponding to each stage of the selection process. In each
%    layer, ones correspond to retained fibers and zeros correspond to
%    rejected fibers
%
%  num_tracked: the number of fibers for each of the following steps:
%    1) the number of fiber tracts generated by fiber_track;
%    2) the number of these tracts that were quantified by fiber_quantifer;
%    3-7) the number of fiber tracts that met criteria 1-5 above, respectively.
%
%  mean_fiber_props: A 3D matrix (rows x columns x 5) containing the mean
%    curvature, pennation, and length values along each of the tracts; the
%    amount of aponeurosis area represented by each tract; and the number of
%    points in each tract
%
%  mean_apo_props: A 1 x 3 vector containing the whole-muscle mean values
%    for curvature, pennation, and fiber tract length, weighted by the
%    amount of aponeurosis area represented by each tract.
%
%OTHER FUNCTIONS IN THE MUSCLE DTI FIBER-TRACKING TOOLBOX
%  For help calculating the diffusion tensor, see <a href="matlab: help signal2tensor2">signal2tensor2</a>.
%  For help defining the mask, see <a href="matlab: help define_muscle">define_muscle</a>.
%  For help defining the ROI, see <a href="matlab: help define_roi">define_roi</a>.
%  For help with the fiber tracking program, see <a href="matlab: help fiber_track">fiber_track</a>.
%  For help smoothing fiber tracts, see <a href="matlab: help fiber_fitter">fiber_smoother</a>.
%  For help quantifying fiber tracts, see <a href="matlab: help fiber_quantifier">fiber_quantifier</a>.
%  For help visualizing the data, see <a href="matlab: help fiber_visualizer">fiber_visualizer</a>.
%
%VERSION INFORMATION
%  v 1.o (initital release), 28 Dec 2020, Bruce Damon
%
%ACKNOWLEDGEMENTS
%  People: Zhaohua Ding, Anneriet Heemskerk
%  Grant support: NIH/NIAMS R01 AR050101, NIH/NIAMS R01 AR073831

%% get options from input structure
min_distance = fg_options.min_distance;
min_pennation = fg_options.min_pennation;
max_pennation = fg_options.max_pennation;
max_curvature = fg_options.max_curvature;

%% intialize output variables

fiber_indices_rows = sum(squeeze(angle_list(:,:,2)), 2);                    %find rows with fiber tracts
fiber_indices_rows = fiber_indices_rows>0;
fiber_indices_cols = sum(squeeze(angle_list(:,:,2)), 1);                    %find columns with fiber tracts
fiber_indices_cols = fiber_indices_cols>0;
first_row = find(fiber_indices_rows, 1);                           %find first and lastrow
last_row = find(fiber_indices_rows, 1, 'last');
first_col = find(fiber_indices_cols, 1);                           %find first and last column
last_col = find(fiber_indices_cols, 1, 'last');

final_fibers=zeros(size(fiber_all));                                        %initialize matrix of fiber fibers; 
final_fibers(first_row:last_row, first_col:last_col, :, :) = ...            %set as tracked fibers; wil prune erroneus results later
    fiber_all(first_row:last_row, first_col:last_col, :, :);
final_angle = angle_list;                                                   %same for geometric measurements of tracts
final_distance = distance_list;
final_curvature = curvature_list;

initial_fibers = zeros(size(roi_flag));                                     %start creating the quality mask
initial_fibers(first_row:last_row, first_col:last_col)=1;
qual_mask = zeros([size(squeeze(fiber_all(:,:,1,1))) 6]);
qual_mask(:,:,1)=roi_flag.*initial_fibers;

%% initialize architecture output variables

mean_angle = sum(angle_list, 3)./squeeze(n_points(:,:,2));
mean_angle(isnan(mean_angle)) = 0;

mean_curvature = sum(curvature_list, 3)./n_points(:,:,3);

total_distance = squeeze(max(distance_list, [], 3));

%% implement quality checking algorithm

%1) reject fibers that do not monotonically increase in the Z direction

z_positions=squeeze(fiber_all(:,:,:,3));
for row_cntr = first_row:last_row
    
    for col_cntr = first_col:last_col
        
        loop_z=squeeze(z_positions(row_cntr, col_cntr,:));                  % z positions for each fiber tract
        loop_z=nonzeros(loop_z);
        loop_dz=diff(loop_z);                                               %find differences between points
        loop_dz=loop_dz(1:(length(loop_dz)-1));
        
        if length(find(loop_dz<0))>0                                        %look for differences < 0 - indicates down-sloping fiber tracts
            qual_mask(row_cntr,col_cntr,1)=0;                               %write to quality mask
        end
        
    end
    
end
num_tracked(1) = length(find(qual_mask(:,:,1)>0));                          %count number passing through this criterion

%2) reject fibers that are too short
too_short = ones(size(total_distance));                                     %initialize as ones matrix
too_short(total_distance<min_distance) = 0;                                 %then find fiber tracts with length<minimum threshold
qual_mask(:,:,2) = qual_mask(:,:,1).*too_short;                             %write to qaulity mask
num_tracked(2) = length(find(qual_mask(:,:,2)>0));                          %count number passing through this criterion

%3) reject fibers that out of bounds pennation angle
angles_out_of_range = ones(size(mean_angle));                             	%initialize as ones matrix
angles_out_of_range(mean_angle <= min_pennation) = 0;                       %then find fiber tracts with pennation<minimum threshold
angles_out_of_range(mean_angle >= max_pennation) = 0;                       %or >maximum threshold
qual_mask(:,:,3) = qual_mask(:,:,2).*angles_out_of_range;                   %write to quality mask
num_tracked(3) = length(find(qual_mask(:,:,3)>0));                          %count number passing through this criterion

%4) reject fibers that have excessive curvature
high_curvature = ones(size(mean_curvature));
high_curvature(mean_curvature >= max_curvature) = 0;
qual_mask(:,:,4) = qual_mask(:,:,3).*high_curvature;
num_tracked(4) = length(find(qual_mask(:,:,4)>0));

%6) reject fibers that are very different (>2 SD) from their neighboring pixels in
%   length, curvature, or pennation angle
qual_mask(:,:,5) = qual_mask(:,:,4);                                        %initialize layers 5 and 6 as = index 4
qual_mask(:,:,6) = qual_mask(:,:,4);

for row_cntr = first_row:last_row
    
    for col_cntr = first_col:last_col
        
        if qual_mask(row_cntr,col_cntr,5) == 1
            
            row_neighbors = (row_cntr-2):(row_cntr+2);                      %find row indices for 24 nearest neighbors
            col_neighbors = (col_cntr-2):(col_cntr+2);                      %find column indices for 24 nearest neighbors
            local_fibers = qual_mask(row_neighbors,col_neighbors,4);        %get the indices from layer 4 of the matrix
            
            local_angle = mean_angle(row_neighbors, col_neighbors);         %get set of local angles
            local_angle = local_angle.*local_fibers;
            local_angle_non0 = local_angle(local_angle>0);
            mean_local_angle = mean(local_angle_non0);                      %get local mean and SD
            std_local_angle = std(local_angle_non0);
            
            if local_angle(3,3)>(mean_local_angle + 2*std_local_angle) || ...   %set outlier criteria
                    local_angle(3,3)<(mean_local_angle - 2*std_local_angle)
                qual_mask(row_cntr,col_cntr,6) = 0;                         %keep track of this in layer 6 so later results are unaffected
            end
            
            local_curve = mean_curvature(row_neighbors, col_neighbors);     %repeat for curvature
            local_curve = local_curve.*local_fibers;
            local_curve_non0 = local_curve(local_curve>0);
            mean_local_curve = median(local_curve_non0);
            std_local_curve = std(local_curve_non0);
            if local_curve(3,3)>(mean_local_curve + 2*std_local_curve) || ...
                    local_curve(3,3)<(mean_local_curve - 2*std_local_curve)
                qual_mask(row_cntr,col_cntr,6) = 0;
            end
            
            local_length = total_distance(row_neighbors, col_neighbors);    %and for distance
            local_length = local_length.*local_fibers;
            local_length_non0 = local_length(local_length>0);
            mean_local_length = median(local_length_non0);
            std_local_length = std(local_length_non0);
            if local_length(3,3)>(mean_local_length + 2*std_local_length) || ...
                    local_length(3,3)<(mean_local_length - 2*std_local_length)
                qual_mask(row_cntr,col_cntr,6) = 0;
            end
            
        end
        
        % eliminate tracts that failed the tests
        final_fibers(row_cntr,col_cntr,:,1) = final_fibers(row_cntr,col_cntr,:,1)*qual_mask(row_cntr,col_cntr,6);
        final_fibers(row_cntr,col_cntr,:,2) = final_fibers(row_cntr,col_cntr,:,2)*qual_mask(row_cntr,col_cntr,6);
        final_fibers(row_cntr,col_cntr,:,3) = final_fibers(row_cntr,col_cntr,:,3)*qual_mask(row_cntr,col_cntr,6);
        
        %eliminate architecgture measurements for failed tracts
        final_curvature(row_cntr,col_cntr,:) = final_curvature(row_cntr,col_cntr,:)*qual_mask(row_cntr,col_cntr,6);
        final_angle(row_cntr,col_cntr,:) = final_angle(row_cntr,col_cntr,:)*qual_mask(row_cntr,col_cntr,6);
        final_distance(row_cntr,col_cntr,:) = final_distance(row_cntr,col_cntr,:)*qual_mask(row_cntr,col_cntr,6);
        
    end
    
end

% calculate output variables, then set index 6 of layer 3 back to zero
num_tracked(5) = length(find(qual_mask(:,:,6)>0));
num_tracked=[(last_row-first_row+1)*(last_col-first_col+1) sum(sum(initial_fibers)) num_tracked];       %add number of potential fiber tracts and umber generated by fiber_track to num_tracked
qual_final = qual_mask(:,:,6);                                                  %selected fibers
qual_final(isnan(mean_angle)) = 0;                                              %but eliminate NaN values
qual_final(isnan(mean_curvature)) = 0;
qual_final(isnan(total_distance)) = 0;
qual_mask(:,:,5) = qual_mask(:,:,6);                                            %rewrite to index five
qual_mask(:,:,6) = 0;                                                           %set back to zero - will only contain numbers if uniform sampling is also used

%mean properties for each tract
mean_curvature = mean_curvature.*qual_mask(:,:,5);                              %get failed fiber tracts out of hte calculation of mean properities
mean_curvature(isnan(mean_curvature)) = 0;                                      %account for division by zero when initially calculating the mean
mean_fiber_props = mean_curvature;                                              %index 1 of third dimension has curvature

mean_angle = mean_angle.*qual_mask(:,:,5);
mean_angle(isnan(mean_angle)) = 0;
mean_fiber_props(:,:,2) = mean_angle;                                         	%index 2 of third dimension has pennation

total_distance = total_distance.*qual_mask(:,:,5);
mean_fiber_props(:,:,3) = total_distance;                                       %index 3 of third dimension has length

mean_fiber_props(:,:,4) = apo_area;                                            	%index 4 of third dimension has aponeurosis area represented by each tract

mean_fiber_props(:,:,5) = n_points(:,:,1).*qual_mask(:,:,5);                    %finally, number of ppints in each tract

%aponeurosis-wide properties - calculate weighted mean (weighted by relative aponeurosis area)
mean_apo_props(1) = sum(sum(mean_curvature.*apo_area.*qual_final))./sum(sum(apo_area.*qual_final));
mean_apo_props(2) = sum(sum(mean_angle.*apo_area.*qual_final))./sum(sum(apo_area.*qual_final));
mean_apo_props(3) = sum(sum(total_distance.*apo_area.*qual_final))./sum(sum(apo_area.*qual_final));

%% if uniform sampling is set as an option:

if isfield(fg_options, 'sampling_frequency') && nargin==9
    
    %will need the roi_mesh area in mm
    dwi_res = fg_options.dwi_res;
    roi_mesh_mm = roi_mesh(:,:,1:3);
    roi_mesh_mm(:,:,1:2) = roi_mesh_mm(:,:,1:2)*dwi_res(1)/dwi_res(2);      %xFOV, /matrix size
    roi_mesh_mm(:,:,3) = roi_mesh_mm(:,:,3)*dwi_res(3);                     %xSlice Thickness
    
    sampling_frequency = fg_options.sampling_frequency;                     %desired sampling frequency,
    
    n_row = length(roi_mesh_mm(:,1,1));
    n_col = length(roi_mesh_mm(1,:,1));
    
    %matrix to hold all dX values (see definitions of temp matrices dX1, dX2, etc.)
    dX_all = zeros(n_row, n_col, 8);
    dY_all = zeros(n_row, n_col, 8);
    dZ_all = zeros(n_row, n_col, 8);
    dTotal_all = zeros(n_row, n_col, 8);
    
    %differences in X positions, within rows and within columns
    dX1 = squeeze(roi_mesh_mm(:,2:end,1)) - squeeze(roi_mesh_mm(:,1:(end-1),1));         	%between points and points immediately to their left in the matrix; {row,column}=1,1 in dX1 is {row,column}=1,2 in roi_mesh
    dX2 = squeeze(roi_mesh_mm(:,1:(end-1),1)) - squeeze(roi_mesh_mm(:,2:end,1));          	%between points and points immediately to their right in the matrix; {row,column}=1,1 in dX2 is {row,column}=1,1 in roi_mesh
    dX3 = squeeze(roi_mesh_mm(2:end,:,1)) - squeeze(roi_mesh_mm(1:(end-1),:,1));           	%between points and points immediately above in the matrix; {row,column}=1,1 in dX3 is {row,column}=2,1 in roi_mesh
    dX4 = squeeze(roi_mesh_mm(1:(end-1),:,1)) - squeeze(roi_mesh_mm(2:end,:,1));            %between points and points immediately below in the matrix; {row,column}=1,1 in dX4 is {row,column}=1,1 in roi_mesh
    
    %transfer these to coordinates that correspond to positions in roi_mesh
    %all data are for rows 2:(end-1) and columns 2:(end-1) of the mesh
    dX_all(2:(n_row-1), 2:(n_col-1), 1) = dX1(2:(end-1), 1:(end-1));
    dX_all(2:(n_row-1), 2:(n_col-1), 2) = dX2(2:(end-1), 2:end);
    dX_all(2:(n_row-1), 2:(n_col-1), 3) = dX3(1:(end-1), 2:(end-1));
    dX_all(2:(n_row-1), 2:(n_col-1), 4) = dX4(2:end, 2:(end-1));
    
    %fill in the diagonals:
    dX_all(:,:,5) = dX_all(:,:,3) + dX_all(:,:,1);                                          %between points and points up (3) and to the left (1)
    dX_all(:,:,6) = dX_all(:,:,3) + dX_all(:,:,2);                                          %between points and points up (3) and to the right (2)
    dX_all(:,:,7) = dX_all(:,:,4) + dX_all(:,:,1);                                          %between points and points down (4) and to the left (1)
    dX_all(:,:,8) = dX_all(:,:,4) + dX_all(:,:,2);                                          %between points and points down (4) and to the right (2)
    
    %differences in Y positions, within rows and within columns
    dY1 = squeeze(roi_mesh_mm(:,2:end,2)) - squeeze(roi_mesh_mm(:,1:(end-1),2));           	%between points and points immediately to their left in the matrix; {row,column}=1,1 in dY1 is {row,column}=1,2 in roi_mesh
    dY2 = squeeze(roi_mesh_mm(:,1:(end-1),2)) - squeeze(roi_mesh_mm(:,2:end,2));           	%between points and points immediately to their right in the matrix; {row,column}=1,1 in dY2 is {row,column}=1,1 in roi_mesh
    dY3 = squeeze(roi_mesh_mm(2:end,:,2)) - squeeze(roi_mesh_mm(1:(end-1),:,2));           	%between points and points immediately above in the matrix; {row,column}=1,1 in dY3 is {row,column}=2,1 in roi_mesh
    dY4 = squeeze(roi_mesh_mm(1:(end-1),:,2)) - squeeze(roi_mesh_mm(2:end,:,2));           	%between points and points immediately below in the matrix; {row,column}=1,1 in dY4 is {row,column}=1,1 in roi_mesh
    
    %transfer these to coordinates that correspond to positions in roi_mesh
    dY_all(2:(n_row-1), 2:(n_col-1), 1) = dY1(2:(end-1), 1:(end-1));
    dY_all(2:(n_row-1), 2:(n_col-1), 2) = dY2(2:(end-1), 2:end);
    dY_all(2:(n_row-1), 2:(n_col-1), 3) = dY3(1:(end-1), 2:(end-1));
    dY_all(2:(n_row-1), 2:(n_col-1), 4) = dY4(2:end, 2:(end-1));
    
    %fill in the diagonals:
    dY_all(:,:,5) = dY_all(:,:,3) + dY_all(:,:,1);                                          %between points and points up (3) and to the left (1)
    dY_all(:,:,6) = dY_all(:,:,3) + dY_all(:,:,2);                                          %between points and points up (3) and to the right (2)
    dY_all(:,:,7) = dY_all(:,:,4) + dY_all(:,:,1);                                          %between points and points down (4) and to the left (1)
    dY_all(:,:,8) = dY_all(:,:,4) + dY_all(:,:,2);                                          %between points and points down (4) and to the right (2)
    
    %differences in Z positions, within rows and within columns
    dZ1 = squeeze(roi_mesh_mm(:,2:end,3)) - squeeze(roi_mesh_mm(:,1:(end-1),3));          	%between points and points immediately to their left in the matrix; {row,column}=1,1 in dZ1 is {row,column}=1,2 in roi_mesh
    dZ2 = squeeze(roi_mesh_mm(:,1:(end-1),3)) - squeeze(roi_mesh_mm(:,2:end,3));           	%between points and points immediately to their right in the matrix; {row,column}=1,1 in dZ2 is {row,column}=1,1 in roi_mesh
    dZ3 = squeeze(roi_mesh_mm(2:end,:,3)) - squeeze(roi_mesh_mm(1:(end-1),:,3));           	%between points and points immediately above in the matrix; {row,column}=1,1 in dZ3 is {row,column}=2,1 in roi_mesh
    dZ4 = squeeze(roi_mesh_mm(1:(end-1),:,3)) - squeeze(roi_mesh_mm(2:end,:,3));           	%between points and points immediately below in the matrix; {row,column}=1,1 in dZ4 is {row,column}=1,1 in roi_mesh
    
    %transfer these to coordinates that correspond to positions in roi_mesh
    dZ_all(2:(n_row-1), 2:(n_col-1), 1) = dZ1(2:(end-1), 1:(end-1));
    dZ_all(2:(n_row-1), 2:(n_col-1), 2) = dZ2(2:(end-1), 2:end);
    dZ_all(2:(n_row-1), 2:(n_col-1), 3) = dZ3(1:(end-1), 2:(end-1));
    dZ_all(2:(n_row-1), 2:(n_col-1), 4) = dZ4(2:end, 2:(end-1));
    
    %fill in the diagonals:
    dZ_all(:,:,5) = dZ_all(:,:,3) + dZ_all(:,:,1);                                          %between points and points up (3) and to the left (1)
    dZ_all(:,:,6) = dZ_all(:,:,3) + dZ_all(:,:,2);                                          %between points and points up (3) and to the right (2)
    dZ_all(:,:,7) = dZ_all(:,:,4) + dZ_all(:,:,1);                                          %between points and points down (4) and to the left (1)
    dZ_all(:,:,8) = dZ_all(:,:,4) + dZ_all(:,:,2);                                          %between points and points down (4) and to the right (2)
    
    %calculate distance to neighbors at each point, in each of the eight directions
    for d_cntr = 1:8
        dTotal_all(:,:,d_cntr) = (squeeze(dX_all(:,:,d_cntr)).^2 + squeeze(dY_all(:,:,d_cntr)).^2 + squeeze(dZ_all(:,:,d_cntr)).^2).^(0.5);
%         dTotal_all(:,:,d_cntr) = dTotal_all(:,:,d_cntr).*qual_final;
    end
    
    %convert to spatial frequency:
    freq_all = 1/dTotal_all;
    freq_all(isinf(freq_all)) = 0;
    
    min_freq = min(min(min(freq_all(find(freq_all)))));
    
    if sampling_frequency > min_freq                                        %if actual frequnecy is lower than that desired, notify the user
        sampling_frequency = min_freq;
        disp(['Minimum observed fiber tract density is 1/' num2str(0.01*round(100*1/sampling_frequency)) 'mm; sampling at this density'])
    end
    sampling_period = 1/sampling_frequency;
    
    %prepare to go through each group of tracts falling within a sampling area
    apo_region_ids = floor((cumsum(dTotal_all(:,:,1), 2) + cumsum(dTotal_all(:,:,3), 1))/sampling_period);            %find all tracts with indices inside of each interval of sampling_period x sampling_period
    qual_mask_temp = qual_mask(:,:,6);
    regional_apo_area = zeros(max(max(apo_region_ids)), 1);                	%zeros matrix to hold total aponeurosis area represented by each set of tracts
    median_penn_angles = zeros(max(max(apo_region_ids)), 1);                %will hold all median pennation angles for each sampling region
    median_curvatures = zeros(max(max(apo_region_ids)), 1);
    median_distances = zeros(max(max(apo_region_ids)), 1);
    
    %go through each unique aponeursis region:
    for k=1:max(max(apo_region_ids))
        
        % get tract indices
        tract_idx = find(apo_region_ids==k);
        
        %get regional aponeurosis area
        regional_apo_area(k) = sum(sum(apo_area(tract_idx)));
        
%         if length(tract_idx)>5                                              %if there are less than five good tracts in a region, skip it
            
            %eliminate tracts that didn't pass quality above
            tract_idx = tract_idx.*qual_final(tract_idx);
            tract_idx= tract_idx(tract_idx>0);
            
            %analyze regional pennation angles
            regional_penn_angles = mean_angle(tract_idx);                   %get all good pennation angles
            median_penn_angles(k) = median(regional_penn_angles);           %find the median
            relative_penn_angles = regional_penn_angles/median_penn_angles(k); %divide every value by the pedian
            relative_penn_angles = abs(relative_penn_angles-1);             %subtract 1 then take the absolute value, so that values near zero are closest to teh median
            
            %repeat for curvature
            regional_curvatures = mean_curvature(tract_idx);
            median_curvatures(k) = median(regional_curvatures);
            relative_curvature = regional_curvatures/median(regional_curvatures);
            relative_curvature = abs(relative_curvature-1);
            
            %repeat for distance:
            regional_distances = total_distance(tract_idx);
            median_distances(k) = median(regional_distances);
            relative_distance = regional_distances/median(regional_distances);
            relative_distance = abs(relative_distance-1);
            
            %now find most typical tract:
            if length(relative_distance)>2
            similarity_idx = sum([relative_penn_angles'; relative_curvature'; relative_distance']);     %sum typicality measurement for all tract
            most_typical = min(similarity_idx);                             %the minimum is the most typical
            most_typical_idx = find(similarity_idx==most_typical(1));       %get its index into the region
            most_typical_tract_idx = tract_idx(most_typical_idx);           %tehn get its index into roi_mesh
            
            %save index in the temporary quality mask
            qual_mask_temp(most_typical_tract_idx) = 1;                     %and set a temporary qual_mask to 1 at the corresponding location
            end
%         end
    end
    
    qual_mask(:,:,6) = qual_mask_temp;                                      %put into index 6 of quality mask
    
    % calculate other output variables - tract-specific properties; as above
    mean_curvature = mean_curvature.*qual_mask(:,:,6);
    mean_curvature(isnan(mean_curvature)) = 0;
    mean_fiber_props = mean_curvature;
    
    mean_angle = mean_angle.*qual_mask(:,:,6);
    mean_angle(isnan(mean_angle)) = 0;
    mean_fiber_props(:,:,2) = mean_angle;
    
    total_distance = total_distance.*qual_mask(:,:,6);
    mean_fiber_props(:,:,3) = total_distance;
    
    mean_fiber_props(:,:,4) = apo_area;
    
    mean_fiber_props(:,:,5) = n_points(:,:,1).*qual_mask(:,:,6);
    
    %aponeurosis-wide properties
    mean_apo_props(1) = sum(median_curvatures.*regional_apo_area)./sum(regional_apo_area);
    mean_apo_props(2) = sum(median_penn_angles.*regional_apo_area)./sum(regional_apo_area);
    mean_apo_props(3) = sum(median_distances.*regional_apo_area)./sum(regional_apo_area);
    
    %reduce the dataset
    for k=1:length(final_fibers(1,1,:,1))
        final_fibers(:,:,k,1) = final_fibers(:,:,k,1).*qual_mask(:,:,6);
        final_fibers(:,:,k,2) = final_fibers(:,:,k,2).*qual_mask(:,:,6);
        final_fibers(:,:,k,3) = final_fibers(:,:,k,3).*qual_mask(:,:,6);
    end
    
end

%% end the function

return;

