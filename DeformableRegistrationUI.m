classdef DeformableRegistrationUI < handle
    % DeformableRegistrationUI - Manually register 2D blockedImages
    %  h = DeformableRegistrationUI(bmov,bfix) launches a GUI which enables
    %  registering two 2D blockedImages using manual control points. First
    %  three control points are registered using an affine transform, and
    %  all subsequent points perform non-rigid (deformable) registration.
    %
    %  Recommended workflow
    %    - Ensure both inputs have sufficient levels to enable quick
    %      viewing. Ideally, the coarsest level is at most the size of the
    %      screen. Use makeMultiLevel2D to add levels if they don't already
    %      exist.
    %    - Use keyboard shortcuts to toggle (t key) between the moving (1
    %      or m key) or fixed (2 or f key) image.
    %    - Use mouse scroll to zoom, click and drag to pan.
    %    - Toggle between the images and identify a prominent feature that
    %      is clearly visible in both images. Double click on this feature
    %      to place a point. Do this on both images. The display will
    %      update to show the registered image based on this point.
    %    - Repeat the previous step two more times. On each addition, the
    %      intermediate registered moving image will be shown.
    %    - This registration happens on the fly, only for the part of the
    %      image being displayed. So when zoomed in, only the region in
    %      view is warped. 
    %    - Skip to export if only rigid, affine transformation is required.
    %    - To add non-rigid (deformable) control points, repeat the
    %      process of placing corresponding points. When the registration
    %      transitions to the non-rigid mode, a deformed grid is shown as a
    %      visual indication for the displacement/deformation field. Update
    %      h.GridSize and h.GridColor to change appearance in the next
    %      refresh.
    %    - Click on a deformable control point in the moving image to bring
    %      up the "impact circle". This circle controls the region around
    %      this point where the corresponding displacement is distributed.
    %      Click and drag the circle to change the radius. 
    %    - Only moving deformable points can be deleted by selecting the
    %      point and hitting the 'delete' key. The corresponding fixed
    %      point is also deleted. Points can be dragged to re-position
    %      anytime.
    %    - To export the final result, call write(h.BMoving,...). See
    %      blockedImage/write for more details.
    %
    % See also: blockedImage, makeMultiLevel2D, blockedImage/write

    properties        
        GridColor = 'k'
        GridSize = [25 25];
    end
    properties (SetAccess = private)
        BMoving (1,1) blockedImage        
    end
    properties (Access=private)
        BMovingOrig (1,1) blockedImage
        
        BFix (1,1) blockedImage

        hFigure
        hAxisMov
        hAxisFix
        hBMoving
        hbFix

        hPointsMov (:,1) images.roi.Point = images.roi.Point.empty()
        hPointsFix (:,1) images.roi.Point = images.roi.Point.empty()
        hPinchLines (:,1) 
        DefaultImpactRadius (1,1) double

        DisplayedImage (1,1) string
        
        GridLinesXFix
        GridLinesYFix
        GridLinesXMov
        GridLinesYMov


        ImpactRadiusCircle

        LabelShowTimer
        StatusHideTimer
        ImpactCircleHideTimer

        TForm

        ActivePoint images.roi.Point
    end

    methods
        function obj = DeformableRegistrationUI(BMoving, bfix)
            arguments
                BMoving (1,1) blockedImage
                bfix (1,1) blockedImage
            end
            obj.BMovingOrig = BMoving;
            obj.BFix = bfix;
            
            obj.DefaultImpactRadius = 0.05*max(obj.BFix.WorldEnd-obj.BFix.WorldStart,[],"all");

            obj.hFigure = figure();
            obj.hFigure.DeleteFcn = @(varargin)obj.delete();
            obj.hAxisMov = axes(Parent=obj.hFigure);
            obj.hAxisFix = axes(Parent=obj.hFigure);
            disableDefaultInteractivity(obj.hAxisMov);
            disableDefaultInteractivity(obj.hAxisFix);
            linkaxes([obj.hAxisFix, obj.hAxisMov])
            obj.hBMoving = bigimageshow(obj.BMovingOrig,Parent=obj.hAxisMov);
            obj.hbFix = bigimageshow(obj.BFix,Parent=obj.hAxisFix);
            % Add title after bigimageshow to retain
            title(obj.hAxisMov,"Moving Image","Press f or 2 for Fixed Image. Or t to toggle.");
            title(obj.hAxisFix,"Fixed Image","Press m or 1 for Moving Image. Or t to toggle");

            obj.hAxisMov.XAxis.LimitsChangedFcn = @(~,~)obj.updateGrid();
            obj.hAxisMov.YAxis.LimitsChangedFcn = @(~,~)obj.updateGrid();

            obj.hFigure.KeyPressFcn = @obj.keyBoardPress;
            % Show moving first
            obj.keyBoardPress([],struct("Key",'m'));

            addlistener(obj.hFigure,"WindowMousePress",@obj.mouseButtonClick);
            addlistener(obj.hFigure,"WindowMouseMotion",@obj.mouseMotion);
        end

        function keyBoardPress(obj,~,hEvt)
            switch (hEvt.Key)
                case {'m','M','1'}
                    obj.hAxisMov.Visible = 'on';
                    set(obj.hAxisMov.Children,'Visible','on')                                  
                    obj.hAxisFix.Visible = 'off';
                    set(obj.hAxisFix.Children,'Visible','off')

                    obj.DisplayedImage = "moving";
                case {'f','F','2'}
                    obj.hAxisMov.Visible = 'off';
                    set(obj.hAxisMov.Children,'Visible','off')
                    obj.hAxisFix.Visible = 'on';
                    set(obj.hAxisFix.Children,'Visible','on')  
                    obj.DisplayedImage = "fixed";
                case {'t','T'}
                    if obj.DisplayedImage=="fixed"
                        hEvt2.Key = 'm';
                    else
                        hEvt2.Key = 'f';
                    end
                    obj.keyBoardPress([],hEvt2);
                case 'delete'
                    obj.removeActivePoint()
            end
            obj.hideImpactRadius();
        end

        function mouseButtonClick(obj,~, ~)
            %TODO - return if moving and deform, but affine is not done yet.
            if obj.DisplayedImage=="moving"
                curAxis = obj.hAxisMov;
                color = 'r';
                if numel(obj.hPointsMov)<3
                    label = "Affine "+num2str(numel(obj.hPointsMov)+1);
                    markerSize = 8;
                    isAffine = true;
                else
                    label = "Deformable "+num2str(numel(obj.hPointsMov)+1);
                    markerSize = 4;
                    isAffine = false;
                end
            else
                curAxis = obj.hAxisFix;
                color = 'g';
                if numel(obj.hPointsFix)<3
                    label = "Affine "+num2str(numel(obj.hPointsFix)+1);
                    markerSize = 8;
                    isAffine = true;
                else
                    label = "Deformable "+num2str(numel(obj.hPointsFix)+1);
                    markerSize = 4;
                    isAffine = false;
                end

            end

            if obj.hFigure.SelectionType =="open"
                isMovingActive = obj.DisplayedImage=="moving";
                if isMovingActive && numel(obj.hPointsMov)==3 && numel(obj.hPointsFix)<3
                    obj.showStatus("Finish placing Affine points on Fixed image")
                    return;
                end
                newPoint = drawpoint(Parent=curAxis,...
                    Position=curAxis.CurrentPoint(1,1:2),...
                    Color=color,MarkerSize=markerSize,...
                    Label=label, LabelAlpha=0.5,...
                    contextMenu=[]);
                addlistener(newPoint,'MovingROI',@obj.hideImpactRadius);
                addlistener(newPoint,'ROIMoved',@obj.updateTransform);
                addlistener(newPoint,'ROIClicked',@obj.pointClicked);

                % Flag to differentiate between the two sets
                newPoint.UserData.IsMoving = isMovingActive;
                newPoint.UserData.IsAffine = isAffine;
                newPoint.UserData.ImpactRadius = obj.DefaultImpactRadius;
                if newPoint.UserData.IsMoving
                    obj.hPointsMov(end+1) = newPoint;
                else
                    obj.hPointsFix(end+1) = newPoint;
                end

                % Manually call the update on point addition.
                obj.updateTransform(newPoint);
            end
        end

        function mouseMotion(obj,~,~)
            set(obj.hPointsMov,'LabelVisible','off');
            set(obj.hPointsFix,'LabelVisible','off');
            if isempty(obj.LabelShowTimer)
                obj.LabelShowTimer = timer('StartDelay',2,...
                    'TimerFcn',@obj.showPointLabels);
            end
            stop(obj.LabelShowTimer);
            start(obj.LabelShowTimer);
        end

        function showPointLabels(obj,~,~)
            set(obj.hPointsMov,'LabelVisible','on');
            set(obj.hPointsFix,'LabelVisible','on');
        end

        function pointClicked(obj, hSrc, ~)
            if hSrc.UserData.IsMoving
                obj.ActivePoint = hSrc;
                obj.showImpactRadius();
            end
        end

        function updateTransform(obj, hEvtPoint,~)
            % Moving point (Note points are handle classes! So this will
            % update information in obj.hPointsMov)
            if hEvtPoint.UserData.IsMoving && hEvtPoint.UserData.IsAffine
                if isempty(obj.TForm)
                    hEvtPoint.UserData.PositionInMoving = ...
                        hEvtPoint.Position;
                else
                    % Shown image is the transformed moving, save the
                    % corresponding points from the original moving
                    hEvtPoint.UserData.PositionInMoving = ...
                        obj.TForm.transformPointsInverse(hEvtPoint.Position);
                end
            end

            if numel(obj.hPointsFix)~=numel(obj.hPointsMov)
                obj.showStatus("Waiting for matching number of points")
                return
            end

            % Compute transform
            srcDefPoints = [];
            dstDefPoints = [];
            impactRadius = [];
            switch numel(obj.hPointsFix)
                case 1
                    movingPoints = vertcat(vertcat(obj.hPointsMov.UserData).PositionInMoving);
                    displacement = obj.hPointsFix(1).Position - movingPoints;
                    affTform = transltform2d(displacement);
                case 2
                    movingPoints = vertcat(vertcat(obj.hPointsMov.UserData).PositionInMoving);
                    affTform = fitgeotform2d(movingPoints,...
                        vertcat(obj.hPointsFix.Position),"similarity");
                case 3
                    movingPoints = vertcat(vertcat(obj.hPointsMov.UserData).PositionInMoving);
                    affTform = fitgeotform2d(movingPoints,...
                        vertcat(obj.hPointsFix(1:3).Position),"affine");
                otherwise % >3
                    movingPoints = vertcat(vertcat(obj.hPointsMov(1:3).UserData).PositionInMoving);
                    affTform = fitgeotform2d(movingPoints(1:3,:),...
                        vertcat(obj.hPointsFix(1:3).Position),"affine");
                    srcDefPoints = vertcat(obj.hPointsMov(4:end).Position);
                    dstDefPoints = vertcat(obj.hPointsFix(4:end).Position);
                    impactRadius = vertcat(vertcat(obj.hPointsMov(4:end).UserData).ImpactRadius);
            end
            obj.TForm = ...
                deformableRegistrationUI.internal.AffineDeformTransform(affTform,srcDefPoints, dstDefPoints,...
                impactRadius);

            % Move the moving points current position to reflect the latest
            % tform.
            for ind = 1:min(3,numel(obj.hPointsMov))
                obj.hPointsMov(ind).Position = ...
                    affTform.transformPointsForward(obj.hPointsMov(ind).UserData.PositionInMoving);
            end

            % Update moving image
            adapter = deformableRegistrationUI.internal.WarpAdapter(AffineDeformTransform=obj.TForm,...
                BlockSize=obj.BMovingOrig.BlockSize(1,:),...
                WorldStart=obj.BFix.WorldStart(1,:),...
                WorldEnd=obj.BFix.WorldEnd(1,:));
            obj.BMoving = blockedImage(obj.BMovingOrig, Adapter=adapter);
            
            obj.hBMoving.CData = obj.BMoving;            
            obj.updateGrid();
        end

        function updateGrid(obj)
            delete(obj.GridLinesYMov)
            delete(obj.GridLinesXMov)
            delete(obj.GridLinesYFix)
            delete(obj.GridLinesXFix)            
            delete(obj.hPinchLines)
            obj.hPinchLines = [];

            if numel(obj.hPointsMov)<4||numel(obj.hPointsFix)<4
                return
            end

            % Initial evenly spaced grid points in moving for the current
            % view window.
            wylimsFix = ylim(obj.hAxisFix);
            wxlimsFix = xlim(obj.hAxisFix);
            [wxlims, wylims]= obj.TForm.transformPointsInverse(wxlimsFix, wylimsFix);
            gridPointsY = linspace(wylims(1),wylims(2),...
                obj.GridSize(1));
            gridPointsX = linspace(wxlims(1),wxlims(2),...
                obj.GridSize(2));                        
            [gridPointsXY(:,:,1), gridPointsXY(:,:,2)] =...
                meshgrid(gridPointsX, gridPointsY);
            
            % Transformed forward into the fixed
            [fgridPointsXY(:,:,1), fgridPointsXY(:,:,2)] = obj.TForm.transformPointsForward(...
                gridPointsXY(:,:,1), gridPointsXY(:,:,2));

            
            hold(obj.hAxisMov,"on")
            hold(obj.hAxisFix,"on")
            obj.GridLinesYMov = plot(fgridPointsXY(:,:,1), fgridPointsXY(:,:,2),'-',...
                Parent=obj.hAxisMov,Color=obj.GridColor,...
                HitTest='off',PickableParts='none');
            obj.GridLinesXMov = plot(fgridPointsXY(:,:,1)', fgridPointsXY(:,:,2)','-',...
                Parent=obj.hAxisMov,Color=obj.GridColor,...
                HitTest='off',PickableParts='none');
            obj.GridLinesYFix = plot(fgridPointsXY(:,:,1), fgridPointsXY(:,:,2),'-',...
                Parent=obj.hAxisFix,Color=obj.GridColor,...
                HitTest='off',PickableParts='none');
            obj.GridLinesXFix = plot(fgridPointsXY(:,:,1)', fgridPointsXY(:,:,2)','-',...
                Parent=obj.hAxisFix,Color=obj.GridColor,...
                HitTest='off',PickableParts='none');

            % Show pinch lines
            delete(obj.hPinchLines)
            for ind=4:numel(obj.hPointsFix)
                length = obj.hPointsFix(ind).Position-obj.hPointsMov(ind).Position;
                obj.hPinchLines(ind-3) = ...
                    quiver(obj.hAxisMov,obj.hPointsMov(ind).Position(1),obj.hPointsMov(ind).Position(2),...
                    length(1),length(2),Color='r',...
                    PickableParts="none");
            end
        end

        function showStatus(obj, statusText)
            if isempty(obj.StatusHideTimer)
                obj.StatusHideTimer = timer('StartDelay',2,...
                    'TimerFcn',@obj.hideStatus);
            end
            stop(obj.StatusHideTimer);
            start(obj.StatusHideTimer);
            xlabel(obj.hAxisMov,statusText);
            xlabel(obj.hAxisFix,statusText);
        end
        function hideStatus(obj,~,~)
            xlabel(obj.hAxisMov,'');
            xlabel(obj.hAxisFix,'');
        end

        function showImpactRadius(obj)
            if isempty(obj.ImpactRadiusCircle)
                obj.ImpactRadiusCircle = drawcircle(...
                    Center=obj.ActivePoint.Position,...
                    Radius=obj.ActivePoint.UserData.ImpactRadius,...
                    Color = 'r',...
                    FaceSelectable=false);
                obj.ImpactCircleHideTimer = timer('StartDelay',6,...
                    'TimerFcn',@obj.hideImpactRadius);
                addlistener(obj.ImpactRadiusCircle,"MovingROI",@obj.impactCircleMoving);
                addlistener(obj.ImpactRadiusCircle,"ROIMoved",@obj.impactCircleMoved);
            end
            stop(obj.ImpactCircleHideTimer);
            obj.ImpactRadiusCircle.Center = obj.ActivePoint.Position;
            obj.ImpactRadiusCircle.Radius = obj.ActivePoint.UserData.ImpactRadius;
            obj.ImpactRadiusCircle.Visible = "on";
            start(obj.ImpactCircleHideTimer);
        end
        function impactCircleMoving(obj,~,~)
            stop(obj.ImpactCircleHideTimer);
            start(obj.ImpactCircleHideTimer);
        end
        function impactCircleMoved(obj,~,~)
            stop(obj.ImpactCircleHideTimer);
            start(obj.ImpactCircleHideTimer);
            if ~isequal(obj.ActivePoint.UserData.ImpactRadius, obj.ImpactRadiusCircle.Radius)
                obj.ActivePoint.UserData.ImpactRadius = obj.ImpactRadiusCircle.Radius;
                % Fire update
                obj.updateTransform(obj.ActivePoint);
            end
        end
        function hideImpactRadius(obj,~,~)
            if isempty(obj.ImpactRadiusCircle) % Not yet shown, nothing to do
                return
            end
            obj.ImpactRadiusCircle.Visible = "off";
            if ~isempty(obj.ActivePoint) && ...
                    ~isequal(obj.ActivePoint.UserData.ImpactRadius, obj.ImpactRadiusCircle.Radius)
                obj.ActivePoint.UserData.ImpactRadius = obj.ImpactRadiusCircle.Radius;
                % Fire update
                obj.updateTransform(obj.ActivePoint);
            end
        end

        function removeActivePoint(obj)
            if ~isempty(obj.ActivePoint)...
                && obj.ImpactRadiusCircle.Visible=="on"...
                && ~obj.ActivePoint.UserData.IsAffine...
                && obj.ActivePoint.UserData.IsMoving
                
                obj.hideImpactRadius();

                delInd = find(obj.ActivePoint == obj.hPointsMov);                
                obj.ActivePoint = images.roi.Point.empty();
                delete(obj.hPointsMov(delInd))
                obj.hPointsMov(delInd) = [];
                if numel(obj.hPointsFix)>=delInd
                    delete(obj.hPointsFix(delInd))
                    obj.hPointsFix(delInd) = [];
                end                
                delete(obj.hPinchLines)
                obj.hPinchLines = [];
                
                obj.updateTransform(obj.hPointsFix(end));                
            end
        end

        function delete(obj)
            if ~isempty(obj.LabelShowTimer)
                stop(obj.LabelShowTimer);
                delete(obj.LabelShowTimer)
            end
            if ~isempty(obj.StatusHideTimer)
                stop(obj.StatusHideTimer)
                delete(obj.StatusHideTimer)
            end
            if ~isempty(obj.ImpactCircleHideTimer)
                stop(obj.ImpactCircleHideTimer)
                delete(obj.ImpactCircleHideTimer)
            end
        end
    end
end

%   Copyright 2023 The MathWorks, Inc.