function [smoothed_fiber_all, fiber_all_mm, smoothed_fiber_all_mm, pcoeff_r, pcoeff_c, pcoeff_s, n_points_smoothed, residuals, residuals_mm] = fiber_smoother(fiber_all, fs_options)
%
%FUNCTION fiber_smoother
%  [smoothed_fiber_all, fiber_all_mm, smoothed_fiber_all_mm, pcoeff_r, pcoeff_c, pcoeff_s,...
%   n_points_smoothed, residuals_r, residuals_c, residuals_s] = ...
%    fiber_smoother(fiber_all, fs_options);
%
%USAGE
%  The function fiber_smoother is used to smooth fiber tracts and increase
%  the spatial resolution of fiber tracts generated using the MuscleDTI_Toolbox. 
%
%  The user inputs the fiber tracts generated by fiber_track and a structure
%  with options for implementing the polynomial fitting routines.  The 
%  [row column slice] positions are separately fitted to Nth-order polynomials
%  as functions of distance in pixel-widths along the tract. The user selects the 
%  polynomial order separately for the row, column, and slice positions.
%  The function returns the smoothed fiber tracts and matrices containing 
%  the polynomial coefficients for each point.
% 
%  To improve fitting and ensure that the fitted tract continues to originate 
%  from the seed point, the seed point is subtracted from the fiber tract 
%  prior to fitting. Then the polyfit function is used to fit the remaining
%  row, column, and slice positions to polynomial functions. Finally, the
%  polyval function is used to solve the polynomials at interpolation 
%  distances of interpolation_step. Tracts with a number of points lower than
%  2-times-the-maximum-polynomial-order are eliminated prior to smoothing.
%
%  This procedure is modified from Damon et al, Magn Reson Imaging, 2012 to: 
%    1) Fit the tract positions as functions of distance rather than point
%       number. This is required for tracking algorithms that use variable
%       step sizes, such as FACT.
%    2) Allow user selection of the polynomial order, including different 
%       polynomial orders for the row/column/slice positions.  
%
%INPUT ARGUMENTS 
%  fiber_all: the original fiber tracts, output from fiber_track. The rows 
%    and columns correspond to locations on the roi_mesh. Dimension 3 gives 
%    point numbers on the tract, and the fourth dimension has row, column, 
%    and slice coordinates, with units of voxels.
%
%  fs_options: a structure containing the following fields:
%    dwi_res: a three element vector with the FOV, (assumed to be the same for
%      the x and y directions), in-plane matrix size, and the slice thickness
%      of the DTI images. The FOV and slice thickness must be specified in mm.
%
%    interpolation_step: the desired interpolation interval for the fitted 
%    fiber tract, in units of pixel-widths.  For example, setting 
%    interpolation_step to 0.25 would interpolate the fiber tract at intervals 
%    of 0.25 pixel widths. 
%
%    p_order: a 3-element vector containing the polynomial orders, [Nr Nc Ns],
%      to use when fitting the tracts
%
%    tract_units: A two-element string variable set to 'vx' if the units of
%      the fiber tracts are voxels and set to 'mm' if the fiber tracts have
%      units of mm. If set to 'vx', the fiber tract coordinates are converted 
%      to units of mm prior to quantification.
%
%OUTPUT ARGUMENTS
%  smoothed_fiber_all: the fiber tracts following Nth order polynomial
%    fitting
%
%  fiber_all_mm: the original fiber tracts in units of mm 
%
%  smoothed_fiber_all_mm: the fiber tracts following Nth order polynomial
%    fitting, in units of mm
%
%  pcoeff_r: a matrix of the Nth order polynomial coefficients for the
%    tracts' row positions 
%
%  pcoeff_c: a matrix of the Nth order polynomial coefficients for the
%    tracts'column positions 
%
%  pcoeff_s: a matrix of the Nth order polynomial coefficients for the
%    tracts' slice positions 
%
%  n_points_smoothed: the number of points in the fitted tracts
%
%  residuals: matrix of size rows (i.e. number of seedpoint rows) by 
%    columns by the maximum-number-of-tract-points by 5.
%    The fourth dimension contains the row, column, and slice polynomial fit
%    residuals (i.e. residuals(row,col,:,1) is the row residuals, etc.), 
%    the point number at which the polynomial was evaluated, and the 
%    percent-of-tract-length at which the polynomial was
%    evaluated.
%
%  residuals_mm: matrix of size rows (i.e. number of seedpoint rows) by 
%    columns by the maximum-number-of-tract-points by 5.
%    The fourth dimension contains the row, column, and slice polynomial fit
%    residuals in units of mm, 
%    the point number at which the polynomial was evaluated, and the 
%    percent-of-tract-length at which the polynomial was
%    evaluated.
%
%OTHER FUNCTIONS IN THE MUSCLE DTI FIBER-TRACKING TOOLBOX
%  For help with anisotropic smoothing, see <a href="matlab: help aniso4D_smoothing">aniso4D_smoothing</a>.
%  For help calculating the diffusion tensor, see <a href="matlab: help signal2tensor2">signal2tensor2</a>.
%  For help defining the muscle mask, see <a href="matlab: help define_muscle">define_muscle</a>.
%  For help defining the aponeurosis ROI, see <a href="matlab: help define_roi">define_roi</a>.
%  For help with fiber tracking, see <a href="matlab: help fiber_track">fiber_track</a>.
%  For help quantifying fiber tracts, see <a href="matlab: help fiber_quantifier">fiber_quantifier</a>.
%  For help selecting fiber tracts following their quantification, see <a href="matlab: help fiber_goodness">fiber_goodness</a>.
%  For help visualizing fiber tracts and other structures, see <a href="matlab: help fiber_visualizer">fiber_visualizer</a>.
%
%VERSION INFORMATION
%  v. 1.0.0 (initial release), 17 Jan 2021, Bruce Damon 
%  v. 1.1.0 (updates - modified how interpolation_step is applied to account for anisotropic voxel dimensions; 
%            updated loop_fiber_length_points to be based on polynomial order;
%            and updated offset steps such that fitted-tract first element exactly matches original seed point position), 30 Sept 2021, Carly Lockard
%  v. 1.2.0 (bug fix - converted fiber tract units in millimeter before performing polynomial fitting;
%            update - added fields DWI_RES and TRACT_UNITS in FS_OPTIONS;
%            update - now returns smoothed fibers both in millimeter (SMOOTHED_FIBER_ALL_MM) and in voxel position (SMOOTHED_FIBER_ALL);
%            18 Oct 2021, Xingyu Zhou, 
%            update - added return of residuals between tracked and smoothed fiber tracts (residuals and residuals_mm) and of fiber_all_mm)
%            22 Oct 2021, Carly Lockard
%
%ACKNOWLEDGEMENTS
%  People: Zhaohua Ding, Anneriet Heemskerk, Carly Lockard, Xingyu Zhou
%  Grant support: NIH/NIAMS R01 AR050101, NIH/NIAMS R01 AR073831

%% prepare
dwi_res = fs_options.dwi_res;
interpolation_step=fs_options.interpolation_step;
p_order=fs_options.p_order;
if length(p_order)==1
    p_order=[p_order p_order p_order];
end

%initialize output variables as zeros matrices
max_length = max(find(squeeze(sum(sum(squeeze(fiber_all(:,:,:,1))))))); %#ok<MXFND>
smoothed_fiber_all_mm = ...
    zeros(length(fiber_all(:,1,1,1)), length(fiber_all(1,:,1,1)), (max_length*ceil(1/interpolation_step)), 3);              %zeros matrix to hold 2nd order smoothed fiber tracts
pcoeff_r = zeros(length(fiber_all(:,1,1,1)), length(fiber_all(1,:,1,1)),(p_order(1)+1));
pcoeff_c = zeros(length(fiber_all(:,1,1,1)), length(fiber_all(1,:,1,1)),(p_order(2)+1));
pcoeff_s = zeros(length(fiber_all(:,1,1,1)), length(fiber_all(1,:,1,1)),(p_order(3)+1));

n_points_smoothed = zeros(length(fiber_all(:,1,1,1)), length(fiber_all(1,:,1,1)));

residuals = NaN(length(fiber_all(:,1,1,1)),length(fiber_all(1,:,1,1)),max_length,5);  
residuals_mm = NaN(length(fiber_all(:,1,1,1)),length(fiber_all(1,:,1,1)),max_length,5); 

%account for spatial resolution of the images
dwi_slicethickness = dwi_res(3);
dwi_fov = dwi_res(1);
dwi_xsize = dwi_res(2);

% convert fiber tracts to mm, if needed
if strcmp(fs_options.tract_units, 'vx') || strcmp(fs_options.tract_units, 'VX')
    fiber_all_mm(:,:,:,1) = squeeze(fiber_all(:,:,:,1))*(dwi_fov/dwi_xsize);                                                %convert fiber tracts in pixels to mm
    fiber_all_mm(:,:,:,2) = squeeze(fiber_all(:,:,:,2))*(dwi_fov/dwi_xsize);
    fiber_all_mm(:,:,:,3) = squeeze(fiber_all(:,:,:,3))*dwi_slicethickness;
elseif strcmp(fs_options.tract_units, 'mm') || strcmp(fs_options.tract_units, 'MM')
    fiber_all_mm = fiber_all;
else
    beep
    error('Aborting fiber_quantifier because of unexpected units for fiber tracts.')
end

%% fit each fiber tract (all operations performed with units = mm)

for row_cntr = 1:length(fiber_all_mm(:,1,1,1))
    for col_cntr = 1:length(fiber_all_mm(1,:,1,1))
        
        loop_fiber_length_points = length(find(fiber_all_mm(row_cntr,col_cntr,:,1)));
        
        if loop_fiber_length_points > (2*(max(p_order)))                                                                    %only keep and smooth tracts that have (2 * the largest polynomial order) points
            
            fiber_distance = squeeze(fiber_all_mm(row_cntr,col_cntr,1:loop_fiber_length_points, :));                        %row, column, and slice positions
            fiber_distance(2:loop_fiber_length_points,1) = diff(fiber_distance(:,1));                                       %pointwise differences in row positions
            fiber_distance(2:loop_fiber_length_points,2) = diff(fiber_distance(:,2));
            fiber_distance(2:loop_fiber_length_points,3) = diff(fiber_distance(:,3));
            fiber_distance(1,:)=0;                                                                                          %initial point has distance of zed
            fiber_distance = cumsum((sum(fiber_distance.^2, 2)).^0.5);                                                      %calculate distances along fiber tract from initial point
            fiber_step = (max(fiber_distance)/(loop_fiber_length_points-1))*interpolation_step;                             %calculate step along fiber to obtain desired number of points, accounting for anisotropic voxel dimensions

            loop_fiber_r = squeeze(fiber_all_mm(row_cntr,col_cntr,1:loop_fiber_length_points, 1));                         	%get raw tract data in row direction
            row_init = loop_fiber_r(1);
            loop_fiber_r = loop_fiber_r - row_init;                                                                         %subtract initial value
            pcoeff_r(row_cntr,col_cntr,:) = polyfit(fiber_distance, loop_fiber_r, p_order(1));                              %get polynomial coefficients
            loop_fitted_fiber_r = polyval(squeeze(pcoeff_r(row_cntr,col_cntr,:)), ...                                       %smoothing in row dir.
                min(fiber_distance):fiber_step:max(fiber_distance));
            loop_fitted_fiber_r = loop_fitted_fiber_r - loop_fitted_fiber_r(1);                                             %subtract new fitting offset from all points 
            loop_fitted_fiber_r = loop_fitted_fiber_r + row_init;                                                           %add back the initial value
            smoothed_fiber_all_mm(row_cntr,col_cntr,1:length(loop_fitted_fiber_r),1) = loop_fitted_fiber_r;                 %copy to output variable
            
            loop_fiber_c = squeeze(fiber_all_mm(row_cntr,col_cntr,1:loop_fiber_length_points, 2));                          %get raw tract data in column direction
            col_init = loop_fiber_c(1);
            loop_fiber_c = loop_fiber_c - col_init;                                                                         %subtract initial value
            pcoeff_c(row_cntr,col_cntr,:) = polyfit(fiber_distance, loop_fiber_c, p_order(2));                              %get polynomial coefficients
            loop_fitted_fiber_c = polyval(squeeze(pcoeff_c(row_cntr,col_cntr,:)), ...                                       %smoothing in column dir.
                min(fiber_distance):fiber_step:max(fiber_distance));  	
            loop_fitted_fiber_c = loop_fitted_fiber_c - loop_fitted_fiber_c(1);                                             %subtract new fitting offset from all points 
            loop_fitted_fiber_c = loop_fitted_fiber_c + col_init;                                                           %add back the initial value
            smoothed_fiber_all_mm(row_cntr,col_cntr,1:length(loop_fitted_fiber_c),2) = loop_fitted_fiber_c;                 	%copy to output variable
            
            loop_fiber_s = squeeze(fiber_all_mm(row_cntr,col_cntr,1:loop_fiber_length_points, 3));                          %get raw tract data in z direction
            slc_init = loop_fiber_s(1);
            loop_fiber_s = loop_fiber_s - slc_init;                                                                         %subtract initial value
            pcoeff_s(row_cntr,col_cntr,:) = polyfit(fiber_distance, loop_fiber_s, p_order(3));                              %get polynomial coefficients
            loop_fitted_fiber_s = polyval(squeeze(pcoeff_s(row_cntr,col_cntr,:)), ...                                       %smoothing in slice dir
                min(fiber_distance):fiber_step:max(fiber_distance));
            loop_fitted_fiber_s = loop_fitted_fiber_s - loop_fitted_fiber_s(1);                                             %subtract new fitting offset from all points 
            loop_fitted_fiber_s = loop_fitted_fiber_s + slc_init;                                                           %add back the initial value
            smoothed_fiber_all_mm(row_cntr,col_cntr,1:length(loop_fitted_fiber_s), 3) = loop_fitted_fiber_s;                %copy to output variable
            
            n_points_smoothed(row_cntr,col_cntr) = length(loop_fitted_fiber_s);
            
            if length(loop_fitted_fiber_s) == length(nonzeros(fiber_all_mm(row_cntr,col_cntr,:,3)))
                residuals_mm(row_cntr,col_cntr,1:loop_fiber_length_points,1) = squeeze(smoothed_fiber_all_mm(row_cntr,col_cntr,1:loop_fiber_length_points,1)-fiber_all_mm(row_cntr,col_cntr,1:loop_fiber_length_points,1));
                residuals_mm(row_cntr,col_cntr,1:loop_fiber_length_points,2) = squeeze(smoothed_fiber_all_mm(row_cntr,col_cntr,1:loop_fiber_length_points,2)-fiber_all_mm(row_cntr,col_cntr,1:loop_fiber_length_points,2));
                residuals_mm(row_cntr,col_cntr,1:loop_fiber_length_points,3) = squeeze(smoothed_fiber_all_mm(row_cntr,col_cntr,1:loop_fiber_length_points,3)-fiber_all_mm(row_cntr,col_cntr,1:loop_fiber_length_points,3));
                residuals_mm(row_cntr,col_cntr,1:loop_fiber_length_points,4) = 1:loop_fiber_length_points;                  %number of points
                residuals_mm(row_cntr,col_cntr,1:loop_fiber_length_points,5) = 100*(1:loop_fiber_length_points)./loop_fiber_length_points; %percent length
            else
            % If smoothed fibers have been interpolated to a different step size, evaluate at original step size of input non-smoothed fiber tracts to allow point-to-point residual calculation
                fiber_step = max(fiber_distance)/(loop_fiber_length_points-1);
                smoothed_fiber_all_mm_orig_inc = ...
                   zeros(length(fiber_all(:,1,1,1)), length(fiber_all(1,:,1,1)), (max_length*ceil(1/interpolation_step)), 3); 
                loop_fitted_fiber_r = polyval(squeeze(pcoeff_r(row_cntr,col_cntr,:)), ...                                    %smoothing in row dir.
                    min(fiber_distance):fiber_step:max(fiber_distance));
                loop_fitted_fiber_r = loop_fitted_fiber_r - loop_fitted_fiber_r(1);                                          %subtract new fitting offset from all points 
                loop_fitted_fiber_r = loop_fitted_fiber_r + row_init;                                                        %add back the initial value
                smoothed_fiber_all_mm_orig_inc(row_cntr,col_cntr,1:length(loop_fitted_fiber_r),1) = loop_fitted_fiber_r;
                loop_fitted_fiber_c = polyval(squeeze(pcoeff_c(row_cntr,col_cntr,:)), ...                                    %smoothing in column dir.
                    min(fiber_distance):fiber_step:max(fiber_distance));  	
                loop_fitted_fiber_c = loop_fitted_fiber_c - loop_fitted_fiber_c(1);                                          %subtract new fitting offset from all points 
                loop_fitted_fiber_c = loop_fitted_fiber_c + col_init;                                                        %add back the initial value
                smoothed_fiber_all_mm_orig_inc(row_cntr,col_cntr,1:length(loop_fitted_fiber_c),2) = loop_fitted_fiber_c;
                loop_fitted_fiber_s = polyval(squeeze(pcoeff_s(row_cntr,col_cntr,:)), ...                                    %smoothing in slice dir
                    min(fiber_distance):fiber_step:max(fiber_distance));
                loop_fitted_fiber_s = loop_fitted_fiber_s - loop_fitted_fiber_s(1);                                          %subtract new fitting offset from all points 
                loop_fitted_fiber_s = loop_fitted_fiber_s + slc_init;                                                        %add back the initial value
                smoothed_fiber_all_mm_orig_inc(row_cntr,col_cntr,1:length(loop_fitted_fiber_s), 3) = loop_fitted_fiber_s;                 residuals_mm(row_cntr,col_cntr,1:loop_fiber_length_points,1) = squeeze(smoothed_fiber_all_mm_orig_inc(row_cntr,col_cntr,1:loop_fiber_length_points,1)-fiber_all_mm(row_cntr,col_cntr,1:loop_fiber_length_points,1));
                residuals_mm(row_cntr,col_cntr,1:loop_fiber_length_points,2) = squeeze(smoothed_fiber_all_mm_orig_inc(row_cntr,col_cntr,1:loop_fiber_length_points,2)-fiber_all_mm(row_cntr,col_cntr,1:loop_fiber_length_points,2));
                residuals_mm(row_cntr,col_cntr,1:loop_fiber_length_points,3) = squeeze(smoothed_fiber_all_mm_orig_inc(row_cntr,col_cntr,1:loop_fiber_length_points,3)-fiber_all_mm(row_cntr,col_cntr,1:loop_fiber_length_points,3));
                residuals_mm(row_cntr,col_cntr,1:loop_fiber_length_points,4) = 1:loop_fiber_length_points;                   %number of points
                residuals_mm(row_cntr,col_cntr,1:loop_fiber_length_points,5) = 100*(1:loop_fiber_length_points)./loop_fiber_length_points; %percent length
            end
        end
    end
end

smoothed_fiber_all(:,:,:,1) = squeeze(smoothed_fiber_all_mm(:,:,:,1))/(dwi_fov/dwi_xsize);                                   %convert fiber tracts in mm to pixels
smoothed_fiber_all(:,:,:,2) = squeeze(smoothed_fiber_all_mm(:,:,:,2))/(dwi_fov/dwi_xsize);
smoothed_fiber_all(:,:,:,3) = squeeze(smoothed_fiber_all_mm(:,:,:,3))/dwi_slicethickness;

for row_cntr = 1:length(fiber_all_mm(:,1,1,1))
    for col_cntr = 1:length(fiber_all_mm(1,:,1,1))
        loop_fiber_length_points = length(find(fiber_all_mm(row_cntr,col_cntr,:,1)));
        if loop_fiber_length_points > (2*(max(p_order))) 
            if length(loop_fitted_fiber_s) == length(nonzeros(fiber_all_mm(row_cntr,col_cntr,:,3)))
                residuals(row_cntr,col_cntr,1:loop_fiber_length_points,1) = squeeze(smoothed_fiber_all(row_cntr,col_cntr,1:loop_fiber_length_points,1)-fiber_all(row_cntr,col_cntr,1:loop_fiber_length_points,1));
                residuals(row_cntr,col_cntr,1:loop_fiber_length_points,2) = squeeze(smoothed_fiber_all(row_cntr,col_cntr,1:loop_fiber_length_points,2)-fiber_all(row_cntr,col_cntr,1:loop_fiber_length_points,2));
                residuals(row_cntr,col_cntr,1:loop_fiber_length_points,3) = squeeze(smoothed_fiber_all(row_cntr,col_cntr,1:loop_fiber_length_points,3)-fiber_all(row_cntr,col_cntr,1:loop_fiber_length_points,3));
                residuals(row_cntr,col_cntr,1:loop_fiber_length_points,4) = 1:loop_fiber_length_points;                      %number of points
                residuals(row_cntr,col_cntr,1:loop_fiber_length_points,5) = 100*(1:loop_fiber_length_points)./loop_fiber_length_points; %percent length
            else
                residuals(row_cntr,col_cntr,1:loop_fiber_length_points,1) = squeeze(smoothed_fiber_all_mm_orig_inc(row_cntr,col_cntr,1:loop_fiber_length_points,1)-fiber_all(row_cntr,col_cntr,1:loop_fiber_length_points,1));
                residuals(row_cntr,col_cntr,1:loop_fiber_length_points,2) = squeeze(smoothed_fiber_all_mm_orig_inc(row_cntr,col_cntr,1:loop_fiber_length_points,2)-fiber_all(row_cntr,col_cntr,1:loop_fiber_length_points,2));
                residuals(row_cntr,col_cntr,1:loop_fiber_length_points,3) = squeeze(smoothed_fiber_all_mm_orig_inc(row_cntr,col_cntr,1:loop_fiber_length_points,3)-fiber_all(row_cntr,col_cntr,1:loop_fiber_length_points,3));
                residuals(row_cntr,col_cntr,1:loop_fiber_length_points,4) = 1:loop_fiber_length_points;                      %number of points
                residuals(row_cntr,col_cntr,1:loop_fiber_length_points,5) = 100*(1:loop_fiber_length_points)./loop_fiber_length_points; %percent length
            end
        end
    end
end


%% end function

return;
