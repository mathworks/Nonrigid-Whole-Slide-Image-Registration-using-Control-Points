classdef WarpAdapter < images.blocked.Adapter

    properties
        OriginalBim

        AffineDeformTransform

        WorldStart
        WorldEnd
        BlockSize
        Info
        PixelSize        
    end
    methods
        function obj = WarpAdapter(options)
            arguments
                options.AffineDeformTransform
                options.WorldStart
                options.WorldEnd
                options.BlockSize
            end

            obj.AffineDeformTransform = options.AffineDeformTransform;
            obj.WorldStart = options.WorldStart;
            obj.WorldEnd = options.WorldEnd;
            obj.BlockSize = options.BlockSize;
        end

        function openToRead(obj, source)
            arguments
                obj
                source (1,1) blockedImage
            end
            obj.OriginalBim = source;
        end

        function info = getInfo(obj)
            info = obj.OriginalBim.Adapter.getInfo();
            numLevels = size(info.Size,1);

            info.WorldStart = repmat(obj.WorldStart,[numLevels 1]);
            info.WorldEnd= repmat(obj.WorldEnd,[numLevels 1]);

            info.IOBlockSize = repmat(obj.BlockSize,[numLevels 1]);

            % TODO - Assumption - worldstart/end are same for all levels!

            % Preserve pixel sizes across levels in output
            obj.PixelSize = info.Size./(obj.OriginalBim.WorldEnd-obj.OriginalBim.WorldStart);

            % Compute output size
            info.Size = ceil(obj.PixelSize.*(info.WorldEnd-info.WorldStart));

            obj.Info = info;
        end

        function data = getIOBlock(obj, ioBlockSub, level)

            % Convert the block indices to pixel subscripts to get the
            % subscript of the top left pixel. Based on the block size,
            % get the subscripts of the bottom right pixel
            blockStartSubYX = (ioBlockSub-1).*obj.BlockSize+1;
            blockEndSubYX = blockStartSubYX + obj.BlockSize-1;

            % Convert the pixel indices to world coordinates. The world
            % coordinates indicate the center of the top left and bottom
            % right pixels of the block in world units
            bimWarpedRef = imref2d(obj.Info.Size(level,:),...
                [obj.WorldStart(2), obj.WorldEnd(2)],[obj.WorldStart(1), obj.WorldEnd(1)]);
            [blockStartWorldX,blockStartWorldY] = ...
                bimWarpedRef.intrinsicToWorld(blockStartSubYX(2), blockStartSubYX(1));
            [blockEndWorldX,blockEndWorldY] = ...
                bimWarpedRef.intrinsicToWorld(blockEndSubYX(2), blockEndSubYX(1));

            % Spatial referencing information for this block (Note: spatial
            % referencing is in x-y order, while blockStart etc are in y-x
            % order).
            outRegionRef = imref2d(obj.BlockSize(1:2));
            % Expand the region outwards by half a pixel to align with the
            % outer edge of the block
            halfPixelWidthYX = obj.PixelSize(level,:)/2;
            outRegionRef.YWorldLimits = [blockStartWorldY-halfPixelWidthYX(1),...
                blockEndWorldY+halfPixelWidthYX(1)];
            outRegionRef.XWorldLimits = [blockStartWorldX-halfPixelWidthYX(2),...
                blockEndWorldX+halfPixelWidthYX(2)];

            % Output bounding box in world coordinates in x-y order
            outbbox = [
                blockStartWorldX blockStartWorldY % top left
                blockStartWorldX blockEndWorldY % bottom left
                blockEndWorldX blockStartWorldY % top right
                blockEndWorldX blockEndWorldY   % bottom right
                ];

            % Get corresponding input region. Note: This region need NOT be
            % rectangular if the transformation includes shear
            [inRegionX, inRegionY] = transformPointsInverse(obj.AffineDeformTransform,outbbox(:,1),outbbox(:,2));

            % Find the corresponding input bounding box
            inbboxStart = [min(inRegionX) min(inRegionY)];
            inbboxEnd   = [max(inRegionX) max(inRegionY)];

            % Move to y-x (row-col) order
            inbboxStart = fliplr(inbboxStart);
            inbboxEnd = fliplr(inbboxEnd);
                        
            if ~isempty(obj.AffineDeformTransform.DisplacementsXY)
                % To prevent boundary artifacts, add a border to the source
                % (else result blocks can have black regions if
                % displacement is too large).
                border = max(abs(obj.AffineDeformTransform.DisplacementsXY));                
                inbboxStart = inbboxStart-border;
                inbboxEnd = inbboxEnd+border;
            end

            % Convert to pixel subscripts
            inbboxStartSub = world2sub(obj.OriginalBim,inbboxStart, Level=level);
            inbboxEndSub = world2sub(obj.OriginalBim,inbboxEnd, Level=level);

            % Read corresponding input region
            inputRegion = getRegion(obj.OriginalBim,...
                inbboxStartSub,inbboxEndSub,Level=level);

            % Get the input region's spatial referencing
            inRegionRef = imref2d(size(inputRegion));

            % Convert the actual read-region pixel's centers back to world
            % coordinates
            readInbboxStart = sub2world(obj.OriginalBim,inbboxStartSub,Level=level);
            readInbboxEnd = sub2world(obj.OriginalBim,inbboxEndSub,Level=level);

            % Convert to pixel edges from pixel centers
            inRegionRef.YWorldLimits = [readInbboxStart(1)-halfPixelWidthYX(1),...
                readInbboxEnd(1)+halfPixelWidthYX(2)];
            inRegionRef.XWorldLimits = [readInbboxStart(2)-halfPixelWidthYX(1),...
                readInbboxEnd(2)+halfPixelWidthYX(2)];

            % Warp this block
            data = imwarp(inputRegion,inRegionRef,...
                obj.AffineDeformTransform,OutputView=outRegionRef);
        end

    end
end


%   Copyright 2023 The MathWorks, Inc.