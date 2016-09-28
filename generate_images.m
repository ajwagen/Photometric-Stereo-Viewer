%
% REQUIREMENTS: Must have export_fig installed and added to path.
%               export_fig can be found here:
%
%               https://www.mathworks.com/matlabcentral/fileexchange/23629-export-fig
%
% DESCRIPTION: Saves two images of surface for stereoscopic viewing
%

load('CAT.mat') % Dataset must contain surface (FXY) and binary mask (M)
FXY(~M) = 1;
surfplot(FXY)

axis off
[az,el] = view;
view([-90, 85]);
export_fig -transparent cat_r.png
view([-90, 95]);
export_fig -transparent cat_l.png
close
clear