classdef AffineDeformTransform < images.geotrans.internal.GeometricTransformation
    properties (Hidden)
        IsBidirectional = false
    end
    properties (Constant)
        Dimensionality = 2
    end
    properties
        AffineTform
        SrcTweakPoints
        DstTweakPoints
        DisplacementsXY
        ImpactRadius
    end

    methods
        function obj = AffineDeformTransform(tform, srcTweakPoints, dstTweakPoints, impactRadius)
            arguments
                tform (1,1) images.geotrans.internal.MatrixTransformation
                srcTweakPoints (:,2) double
                dstTweakPoints (:,2) double
                impactRadius (:,1) double
            end
            obj.AffineTform = tform;
            obj.SrcTweakPoints = srcTweakPoints;
            obj.DstTweakPoints = dstTweakPoints;
            obj.ImpactRadius = impactRadius;

            obj.DisplacementsXY = obj.DstTweakPoints - obj.SrcTweakPoints;
        end

        function [srcX, srcY] = transformPointsInverse(obj, dstX, dstY)
            if nargin==2 % packed
                dstY = dstX(:,2);
                dstX = dstX(:,1);
            end
            % First - apply inverse displacement field.
            direction = -1;
            [defX, defY] = obj.applyDeformation(dstX, dstY,direction);
            % Second - inverse affine
            [srcX, srcY] = obj.AffineTform.transformPointsInverse(defX,defY);

            if nargin==2 % pack
                srcX = [srcX, srcY];
            end
        end

        function [dstX, dstY] = transformPointsForward(obj, srcX, srcY)
            if nargin==2 % packed
                srcY = srcX(:,2);
                srcX = srcX(:,1);
            end

            % First- affine
            [dstX, dstY] = obj.AffineTform.transformPointsForward(srcX, srcY);
            % Second - apply forward displacement field.
            direction = 1;
            [dstX, dstY] = obj.applyDeformation(dstX, dstY,direction);
            
            if nargin==2 % pack
                dstX = [dstX, dstY];
            end
        end        
    end

    methods (Access=private)
        function [defX, defY] = applyDeformation(obj, dstX,dstY,direction)
            defX=dstX;defY=dstY;
            % Loop through each tweak point and add/sub its contribution
            for ind = 1:size(obj.DisplacementsXY,1)
                % Euclidean distance to each of the tweak point source
                srcTweakPointX = obj.SrcTweakPoints(ind,1);
                srcTweakPointY = obj.SrcTweakPoints(ind,2);
                dist = sqrt((dstX-srcTweakPointX).^2+(dstY-srcTweakPointY).^2);
                % ImpactRadius weight based on distance
                weight = exp(-(((dist).^2)/(2*obj.ImpactRadius(ind).^2)));
                defX = defX+direction*obj.DisplacementsXY(ind,1).*weight;
                defY = defY+direction*obj.DisplacementsXY(ind,2).*weight;
            end
        end
    end
end

% TODO - Add 'pin points'. These should not move, so attenuate the
% deformation field to 0 starting with the corresponding pin points impact
% radius.

%   Copyright 2023 The MathWorks, Inc.