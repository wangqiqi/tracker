function [positions, time,framecount] = trackertry2(fullfilename,  ...
	padding, kernel, lambda, output_sigma_factor, interp_factor, cell_size, ...
	features)
%TRACKER Kernelized/Dual Correlation Filter (KCF/DCF) tracking.
%   This function implements the pipeline for tracking with the KCF (by
%   choosing a non-linear kernel) and DCF (by choosing a linear kernel).
%
%   It is meant to be called by the interface function RUN_TRACKER, which
%   sets up the parameters and loads the video information.
%
%   Parameters:
%     VIDEO_PATH is the location of the image files (must end with a slash
%      '/' or '\').
%     IMG_FILES is a cell array of image file names.
%     POS and TARGET_SZ are the initial position and size of the target
%      (both in format [rows, columns]).
%     PADDING is the additional tracked region, for context, relative to 
%      the target size.
%     KERNEL is a struct describing the kernel. The field TYPE must be one
%      of 'gaussian', 'polynomial' or 'linear'. The optional fields SIGMA,
%      POLY_A and POLY_B are the parameters for the Gaussian and Polynomial
%      kernels.
%     OUTPUT_SIGMA_FACTOR is the spatial bandwidth of the regression
%      target, relative to the target size.
%     INTERP_FACTOR is the adaptation rate of the tracker.
%     CELL_SIZE is the number of pixels per cell (must be 1 if using raw
%      pixels).
%     FEATURES is a struct describing the used features (see GET_FEATURES).
%     SHOW_VISUALIZATION will show an interactive video if set to true.
%
%   Outputs:
%    POSITIONS is an Nx2 matrix of target positions over time (in the
%     format [rows, columns]).
%    TIME is the tracker execution time, without video loading/rendering.
%
%   Joao F. Henriques, 2014


	%if the target is large, lower the resolution, we don't need that much
	%detail
    vidReader = VideoReader(fullfilename);
    framecount = vidReader.NumberOfFrames;
    vidReader = VideoReader(fullfilename);
    
    %% elle se�me
%     im = readFrame(vidReader);
%     imshow(im);
%     rect = getrect;
%     target_sz = [rect(4), rect(3)];
%  	pos = [rect(2), rect(1)] + floor(target_sz/2);
    %% optical flow ile otomatik se�me
 
    opticFlow = opticalFlowHS;
    im = readFrame(vidReader);
    frameGray = rgb2gray(im);
    flow = estimateFlow(opticFlow,frameGray); 

    im = readFrame(vidReader);
    frameGray = rgb2gray(im);
    
    flow = estimateFlow(opticFlow,frameGray); 

    fm = flow.Magnitude;
    bfm = fm > 0.01;
%     imshow(bfm)
    frameMedian = medfilt2(bfm);        % median filter
%     imshow(frameMedian)
    se = strel('disk',45);
    closeBW = imclose(frameMedian,se);  % morphological close
    
    %% original image i�in yeni de�erler uygulanmal�, 480x640 i�in bu iyi,de�i�meli
    %se1 = strel('line',11,90);%480x640 i�in bu iyi
    se1 = strel('line',11,90);
    erodedBW = imerode(closeBW,se1);    % erode
%     imshow(erodedBW);
    [count,x,y,width,height] = blob(erodedBW);
    count = count - 1;
    target_sz_v= zeros(count,2);
    pos_v = zeros(count,2);
    for i=1:count
        target_sz_v(i,:) = [height(i), width(i)];
        pos_v(i,:) = [y(i), x(i)]+ floor(target_sz_v(i,:)/2);%merkez
    end
%% devam
%     imshow(im)
%     hold on;
%     for i = 1:count        
%         %rectangle('Position',[y(i),x(i),height(i),width(i)],'EdgeColor','r');
%         rectangle('Position',[pos_v(i,1) - floor(target_sz_v(i,1)/2),pos_v(i,2) - floor(target_sz_v(i,2)/2),...
%             target_sz_v(i,1), target_sz_v(i,2)],'EdgeColor','r');
%     end
%     hold off;
    pos = [pos_v(2,2) pos_v(2,1)];
    target_sz = [target_sz_v(2,2) target_sz_v(2,1)];
	resize_image = (sqrt(prod(target_sz)) >= 100);  %diagonal size >= threshold
	if resize_image,
		pos = floor(pos / 2);
		target_sz = floor(target_sz / 2);
	end


	%window size, taking padding into account
	window_sz = floor(target_sz * (1 + padding));
	
% 	%we could choose a size that is a power of two, for better FFT
% 	%performance. in practice it is slower, due to the larger window size.
% 	window_sz = 2 .^ nextpow2(window_sz);

	
	%create regression labels, gaussian shaped, with a bandwidth
	%proportional to target size
	output_sigma = sqrt(prod(target_sz)) * output_sigma_factor / cell_size;
	yf = fft2(gaussian_shaped_labels(output_sigma, floor(window_sz / cell_size)));

	%store pre-computed cosine window
	cos_window = hann(size(yf,1)) * hann(size(yf,2))';		
	
	%note: variables ending with 'f' are in the Fourier domain.

	time = 0;  %to calculate FPS

	positions = zeros(framecount, 2);  %to calculate precision
    frame = 1;
    issame = 0;
	while hasFrame(vidReader),
        
		%load image
        if frame ~= 1,
            im = readFrame(vidReader);
        end
		if size(im,3) > 1,
			im = rgb2gray(im);
		end
		if resize_image,
			im = imresize(im, 0.5);
        end
        if frame ~= 1,
            issame = psnr(im,imtut) > 30;%max(abs(im(:)-imtut(:))) > 50;%
        end
        if issame == 0,
            tic()

            if frame > 1,
                %obtain a subwindow for detection at the position from last
                %frame, and convert to Fourier domain (its size is unchanged)
                patch = get_subwindow(im, pos, window_sz);
                zf = fft2(get_features(patch, features, cell_size, cos_window));
			
                %calculate response of the classifier at all shifts
                switch kernel.type
                case 'gaussian',
                    kzf = gaussian_correlation(zf, model_xf, kernel.sigma);
                case 'polynomial',
                    kzf = polynomial_correlation(zf, model_xf, kernel.poly_a, kernel.poly_b);
                case 'linear',
                    kzf = linear_correlation(zf, model_xf);
                end
                response = real(ifft2(model_alphaf .* kzf));  %equation for fast detection

                %target location is at the maximum response. we must take into
                %account the fact that, if the target doesn't move, the peak
                %will appear at the top-left corner, not at the center (this is
                %discussed in the paper). the responses wrap around cyclically.
                [vert_delta, horiz_delta] = find(response == max(response(:)), 1);
                if vert_delta > size(zf,1) / 2,  %wrap around to negative half-space of vertical axis
                    vert_delta = vert_delta - size(zf,1);
                end
                if horiz_delta > size(zf,2) / 2,  %same for horizontal axis
                    horiz_delta = horiz_delta - size(zf,2);
                end
                pos = pos + cell_size * [vert_delta - 1, horiz_delta - 1];
            end

            %obtain a subwindow for training at newly estimated target position
            patch = get_subwindow(im, pos, window_sz);
            xf = fft2(get_features(patch, features, cell_size, cos_window));

            %Kernel Ridge Regression, calculate alphas (in Fourier domain)
            switch kernel.type
            case 'gaussian',
            	kf = gaussian_correlation(xf, xf, kernel.sigma);
            case 'polynomial',
            	kf = polynomial_correlation(xf, xf, kernel.poly_a, kernel.poly_b);
            case 'linear',
                kf = linear_correlation(xf, xf);
            end
            alphaf = yf ./ (kf + lambda);   %equation for fast training

            if frame == 1,  %first frame, train with a single image
                model_alphaf = alphaf;
                model_xf = xf;
            else
                %subsequent frames, interpolate model
                model_alphaf = (1 - interp_factor) * model_alphaf + interp_factor * alphaf;
                model_xf = (1 - interp_factor) * model_xf + interp_factor * xf;
            end

            %save position and timing
            positions(frame,:) = pos;
            time = time + toc();
            %visualization
            imshow(im);
            hold on;
            rectangle('Position',[pos(2) - floor(target_sz(2)/2),pos(1) - floor(target_sz(1)/2),...
            target_sz(2), target_sz(1)],'EdgeColor','g');            
            hold off;
            str = sprintf('C:/Users/mohkargan/Desktop/best/trackerframes/2/%d%s',frame,'.jpg');
            saveas(gcf,str);
            frame = frame + 1;
            imtut = im;
        end
    end
	if resize_image,
		positions = positions * 2;
	end
end

