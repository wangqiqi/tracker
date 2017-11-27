function [positions, time,frame] = trackermulti(pathname,filename,  ...
	padding, kernel, lambda, output_sigma_factor, interp_factor, cell_size, ...
	features)
    fullfilename = fullfile(pathname,filename);

    vidReader = VideoReader(fullfilename);
    framecount = vidReader.NumberOfFrames;
    vidReader = VideoReader(fullfilename);
    
    save_path = sprintf('%s%s%s/',pathname,'/frames_',filename);
    mkdir(save_path);
    
    %% elle se�me
%     im = readFrame(vidReader);
%     imshow(im);
%     rect = getrect;
%     target_sz = [rect(4), rect(3)];
%  	pos = [rect(2), rect(1)] + floor(target_sz/2);
    %% optical flow ile otomatik se�me
        %% without ofmod func

%     opticFlow = opticalFlowHS;
%     im = readFrame(vidReader);
%     frameGray = rgb2gray(im);
    
%     flow = estimateFlow(opticFlow,frameGray); 
% 
%     im = readFrame(vidReader);
%     frameGray = rgb2gray(im);
%     flow = estimateFlow(opticFlow,frameGray); 
% 
%     fm = flow.Magnitude;
%     bfm = fm > 0.01;
%     frameMedian = medfilt2(bfm);        % median filter
%     %%original image i�in yeni degerler uygulanmali, 480x640 i�in 15 iyi
%     se = strel('disk',45);
%     closeBW = imclose(frameMedian,se);  % morphological close
%     
%     se1 = strel('line',11,90);
%     erodedBW = imerode(closeBW,se1);    % erode
%     [count,x,y,width,height] = blob(erodedBW);
%     count = count - 1;
    
        %% with ofmod func
    opticFlow = opticalFlowHS;
    im1 = readFrame(vidReader);
    frameGray1 = rgb2gray(im1);
%     im2 = readFrame(vidReader);
%     frameGray2 = rgb2gray(im2); 
%     im3 = readFrame(vidReader);
%     frameGray3 = rgb2gray(im3);
    im = readFrame(vidReader);
    whilecount = 0;
    while psnr(im,im1) > 40;
        im = readFrame(vidReader);
        whilecount = whilecount + 1;
    end
    frameGray = rgb2gray(im);

    [count,x,y,width,height] = ofmod(opticFlow,frameGray1, frameGray);
    
    %% merkezi ve pencere buyuklugunu belirle
    target_sz= zeros(count,2);
    pos = zeros(count,2);
    for i=1:count
        target_sz(i,:) = [width(i), height(i)];
        pos(i,:) = [x(i), y(i)]+ floor(target_sz(i,:)/2);%merkez
    end
%% devam
%     imshow(im)
%     hold on;
%     for i = 1:count        
%         rectangle('Position',[pos(i,2) - floor(target_sz(i,2)/2),pos(i,1) - floor(target_sz(i,1)/2),...
%                         target_sz(i,2), target_sz(i,1)],'EdgeColor','r');
%     end
%     hold off;

%     pos = [pos(:,2) pos(:,1)];
%     target_sz = [target_sz(:,2) target_sz(:,1)];

    resize_image = 0;
    for i=1:count
        if (sqrt(prod(target_sz)) >= 100) == 1
            resize_image = 1;
            break;
        end
    end
    
	if resize_image,
		pos = floor(pos / 2);
		target_sz = floor(target_sz / 2);
    end
    
    window_sz = zeros(count,2);
    yf = cell(count,1);
    cos_window = cell(count,1);
    for i=1:count
        %window size, taking padding into account
        window_sz(i,:) = floor(target_sz(i) * (1 + padding));

        %create regression labels, gaussian shaped, with a bandwidth
        %proportional to target size
        output_sigma = sqrt(prod(target_sz(i,:))) * output_sigma_factor / cell_size;
        yf{i} = fft2(gaussian_shaped_labels(output_sigma, floor(window_sz(i,:) / cell_size)));

        %store pre-computed cosine window
        cos_window{i} = hann(size(yf{i},1)) * hann(size(yf{i},2))';		
    end
	%note: variables ending with 'f' are in the Fourier domain.

	time = 0;  %to calculate FPS

	positions = zeros(count,framecount, 2);  %to calculate precision
    frame = 1;
    issame = 0;
    
    patch = cell(count,1);
    zf = cell(count,1);
    kzf = cell(count,1);
    model_xf = cell(count,1);
    kf = cell(count,1);
    xf = cell(count,1);
    alphaf = cell(count,1);
    model_alphaf = cell(count,1);
    poscount = zeros(count,1);
    
	while hasFrame(vidReader),
        %% 20 frame boyunca ayni pozisyondaysa trackerdan sil
        tempcount = count;
        tempposcount = poscount;
        forcount = 1;
        temptarget_sz = target_sz;
        temppos = pos;
        tempwindow_sz = window_sz;
        for i = 1:count,
            if (poscount(i)>20),
                tempcount = tempcount - 1;
                patch(i,:) = [];
                zf(i,:) = [];
                kzf(i,:) = [];
                model_xf(i,:) = [];
                kf(i,:) = [];
                xf(i,:) = [];
                alphaf(i,:) = [];
                model_alphaf(i,:) = [];
                yf(i,:) = [];
                cos_window(i,:) = [];
            else
                tempposcount(forcount) = poscount(i);
                temptarget_sz(forcount,:) = target_sz(i,:);
                temppos(forcount,:) = pos(i,:);
                tempwindow_sz(forcount,:) = window_sz(i,:);
                forcount = forcount + 1;
            end
        end
        if count ~=0,
            poscount = tempposcount(1:tempcount);
            target_sz = temptarget_sz(1:tempcount,:);
            pos = temppos(1:tempcount,:);
            window_sz = tempwindow_sz(1:tempcount,:);
            count = tempcount;
        end
        %% eger takip edilecek bisey kalmad?ysa okumay? b?rak
        if count == 0,
            disp('Takip edilecek hareketli cisim bulunamad?/kalmad?.')
            close all;
            break;
        end
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
            issame = psnr(im,imtut) > 40;%max(abs(im(:)-imtut(:))) > 50;%
        end
        
        if issame == 0,
            tic()
            for i = 1:count
                if frame > 1,
                    %obtain a subwindow for detection at the position from last
                    %frame, and convert to Fourier domain (its size is unchanged)
                    patch{i} = get_subwindow(im, pos(i,:), window_sz(i,:));
                    zf{i} = fft2(get_features(patch{i}, features, cell_size, cos_window{i}));
			
                    %calculate response of the classifier at all shifts
                    switch kernel.type
                    case 'gaussian',
                        kzf{i} = gaussian_correlation(zf{i}, model_xf{i}, kernel.sigma);
                    case 'polynomial',
                        kzf{i} = polynomial_correlation(zf{i}, model_xf{i}, kernel.poly_a, kernel.poly_b);
                    case 'linear',
                        kzf{i} = linear_correlation(zf{i}, model_xf{i});
                    end
                    response = real(ifft2(model_alphaf{i} .* kzf{i}));  %equation for fast detection

                    %target location is at the maximum response. we must take into
                    %account the fact that, if the target doesn't move, the peak
                    %will appear at the top-left corner, not at the center (this is
                    %discussed in the paper). the responses wrap around cyclically.
                    [vert_delta, horiz_delta] = find(response == max(response(:)), 1);                   
                    
                    if vert_delta > size(zf{i},1) / 2,  %wrap around to negative half-space of vertical axis
                        vert_delta = vert_delta - size(zf{i},1);
                    end
                    if horiz_delta > size(zf{i},2) / 2,  %same for horizontal axis
                        horiz_delta = horiz_delta - size(zf{i},2);
                    end                   
                    pos(i,:) = pos(i,:) + cell_size * [vert_delta - 1, horiz_delta - 1];
                    %% target size denemesi
%                     if vert_delta ~= 1 && horiz_delta ~= 1,
%                         [vert_area, horiz_area] = find(response > 0.85*max(response(:)));
%                         for j=1:size(vert_area,1)
%                             if vert_area(j) > size(zf{i},1) / 2,  %wrap around to negative half-space of vertical axis
%                                 vert_area(j) = vert_area(j) - size(zf{i},1);
%                             end
%                             if horiz_area(j) > size(zf{i},2) / 2,  %same for horizontal axis
%                                 horiz_area(j) = horiz_area(j) - size(zf{i},2);
%                             end 
%                         end
%                     end
                end

                %obtain a subwindow for training at newly estimated target position
                patch{i} = get_subwindow(im, pos(i,:), window_sz(i,:));
                xf{i} = fft2(get_features(patch{i}, features, cell_size, cos_window{i}));

                %Kernel Ridge Regression, calculate alphas (in Fourier domain)
                switch kernel.type
                case 'gaussian',
                    kf{i} = gaussian_correlation(xf{i}, xf{i}, kernel.sigma);
                case 'polynomial',
                    kf{i} = polynomial_correlation(xf{i}, xf{i}, kernel.poly_a, kernel.poly_b);
                case 'linear',
                    kf{i} = linear_correlation(xf{i}, xf{i});
                end
                alphaf{i} = yf{i} ./ (kf{i} + lambda);   %equation for fast training

                if frame == 1,  %first frame, train with a single image
                    model_alphaf{i} = alphaf{i};
                    model_xf{i} = xf{i};
                else
                    %subsequent frames, interpolate model
                    model_alphaf{i} = (1 - interp_factor) * model_alphaf{i} + interp_factor * alphaf{i};
                    model_xf{i} = (1 - interp_factor) * model_xf{i} + interp_factor * xf{i};
                end

                %save position and timing
                positions(i,frame,:) = pos(i,:);
                if frame > 1,
                    if positions(i,frame,:) == positions(i,frame-1,:),
                        poscount(i) = poscount(i) + 1;
                    else
                        poscount(i) = 0;
                    end
                end
            end
            time = time + toc();
            %visualization
            imshow(im);
            hold on;
            for i = 1:count
            	rectangle('Position',[pos(i,2) - floor(target_sz(i,2)/2),pos(i,1) - floor(target_sz(i,1)/2),...
                        target_sz(i,2), target_sz(i,1)],'EdgeColor','r');
            end
            hold off;
            str = sprintf('%s%d%s',save_path,frame,'.jpg');
            saveas(gcf,str);
            frame = frame + 1;
        end
        imtut = im;
    end
    frame = frame - 1;
% 	if resize_image,
% 		positions = positions * 2;
% 	end
end

