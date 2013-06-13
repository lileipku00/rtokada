function varargout=rtokadawv(workpath,outpath,runName,runID,stasuffix,lambda,G,GSF,Gwv,stations,t_gauges,gauges,dataflag)

% 05/2013 (DM)
%
% A static slip inversion routine with laplacian regularization and bounds on the lateral and bottom edges of a fault.
%
% This is a modified version of B.Crowell's rtokada routine modified to include wave gauges in the inversion process and generally 
% streamlined and optimized for batch runs. THIS DEPRECATES THE ORIGINAL rtokada() FUNCTION.
%
% INPUT VARS
% workpath
% outpath
% runName
% runID
% stasuffix
% lambda
% G
% GSF
% Gwv
% weightflag
% stations
% t_gauges
% gauges
% dataflag
%
% OUTPUT VARS




%SETUP
format long
cd(workpath)
usegps=dataflag(1);  %Which data to fit
usewave=dataflag(2);


%LOAD FAULT MODEL
f2=load('faults_def_small.txt'); %No of fault elements
ast=f2(1);%along strike elements
adi=f2(2);%along dip elements
[xs,ys,zs,xf1,xf2,xf3,xf4,yf1,yf2,yf3,yf4,zf1,zf2,zf3,zf4,strike,dip,len,width,area]=...
    textread('small_fault.dat','%f %f %f %f %f %f %f %f %f %f %f %f %f %f %f %f %f %f %f %f');
[site latinv,loninv]=textread(stations,'%f %f %f');
[latsf lonsf]=textread('seafloor.xy','%f%f');


%REGULARIZATION
%This section computes the regularization matrix to be appended to the bottom of the Green's Function matrix.  It aims to 
%reduce the laplacian between individual fault segments.  To find the nearest segments, it computes the total distance between the
%center of each fault segment and finds the ones "touching" each other
NW=adi-1;
NL=ast-1; %No of fault patches
k=1;
T=[];
for j = 1:NW%put 1 to clamp top or 2 to unclamp top
    for i = 1:NL
        for m = 1:2
            index1 = (j-1)*NL+i;
            index2 = (j-1)*NL+i-1;
            index3 = (j-1)*NL+i+1;
            index4 = (j-2)*NL+i;
            index5 = (j)*NL+i;
            dx = max(len)/len(index1);
            dy = max(width)/width(index1);
            if (index1 >= 1 && index1 <= length(xs))
                T(k,2*(index1-1)+m) = -2*(dx^-2+dy^-2);
            end
            if (index2 >= 1 && index2 <= length(xs))
                T(k,2*(index2-1)+m) = dx^-2;
            end
            if (index3 >= 1 && index3 <= length(xs))
                T(k,2*(index3-1)+m) = dx^-2;
            end
            if (index4 >= 1 && index4 <= length(xs) )
                T(k,2*(index4-1)+m) = dy^-2;
            end
            if (index5 >= 1 && index5 <= length(xs))
                T(k,2*(index5-1)+m) = dy^-2;
            end
            k=k+1;
        end
    end
end
[h1,h2]=size(T);
Tzeros=zeros(h1,1);

%CREAT MAX SLIP BOUNDS
%Create lower and upper bounds for each fault segment.  It is set up to lock the sides and bottom, and allows the rest of the fault 
%segments to move up to 100 meters in either direction. For positivity, the lower or upper bound needs to be set to zero,
%depending on the sign of slip/strike
eb=1e-2;%maximum displacement the sides and bottom can move, in m
kk=1;
for j=1:NW
    for k=1:NL
        if (k == 1 || k == NL || j == NW)
            lb(kk,1)=-eb;
            ub(kk,1)=eb;
            lb(kk+1,1)=-eb;
            ub(kk+1,1)=eb;
        else
            %These are for strike slip
            lb(kk,1)=-100;
            ub(kk,1)=100;
            %These are for dip slip (mostly thrust)
            lb(kk+1,1)=-1;
            ub(kk+1,1)=100;
            %             lb(kk+1,1)=-1;  %For checkerboard stuff
            %             ub(kk+1,1)=2000;
        end
        kk=kk+2;
    end
end

%READ DATA
U=[]; %Data vector
Sxyz=[];
StaRem=[];
%Read land station coseismic offsets
for j = 1:length(site)
    siter = site(j);
    siterb=num2str(siter);
    %y is north, x is east, z is up
    [t,dy,dx,dz,sy,sx,sz]=textread(['neufiles/' siterb '.' stasuffix '.txt'],'%f %f %f %f %f %f %f');
    ux=dx;
    uy=dy;
    uz=dz;
    %Normalize the data weights
    sd=min([sx sy sz]);
    sx=sx/sd;
    sy=sy/sd;
    sz=sz/sd;
    Sxyz=[Sxyz ; sx ; sy ; sz];
    Ucurrent = [ux;uy;uz];
    U=[U;Ucurrent];
end
%Normalize weight of land GPS stations to a 1 %Maybe try weighting by
%the eman of the noise??
if usegps==0 %Don't care about fitting coseismics
    gpsmult=1e-20;
else %Fit Coseismics at normal level
    gpsmult=1;
end
if usewave==0
    wavemult=1e-20;
else
    wavemult=1;
end

%Read wave gauges
for j=1:length(gauges)
    %First entry is weight, rest is time series
    [tg eta]=textread(['gauges/' gauges{j} '.txt'],'%f%f');
    eta=eta(2:end);
    w=(ones(size(eta))/tg(1))/wavemult;
    Sxyz=[Sxyz ; w];
    U=[U ; eta];
end
%Create matrix of station weights
W=diag(1./Sxyz);

% INVERSION
Ginv = G; 
%Add tsunami GFs
Ginv=[Ginv ; Gwv]; %Will be modified by data weights, etc.
Gforward=Ginv; %Won't me modified further
%Apply weights to data and add zero rows
Uinv=[W*U;Tzeros];
T=T*lambda; %Apply smoothing parameter
Ginv=[W*Ginv;T];%append the regularization onto the greens function
S=lsqlin(Ginv,Uinv,[],[],[],[],lb,ub);%solve for fault motions, in mm
Uforward = Gforward*S;%%%forward model with original green's function
ngps=size(G,1)/3;
%Divide into GPS and wave gauge data
Uforward_gps=Uforward(1:ngps);
U_gps=U(1:ngps);
Uforward_wv=Uforward(ngps+1:end);
U_wv=U(ngps+1:end);
%Get post-inversion metrics
%get L2 norm of misfit
L2=norm(W*U-W*Uforward,2);
%get seminorm of Model
LS=norm(T*S,2);
%get generalized cross validation value
ndata=length(U);
GW=W*Gforward;
Gsharp=(GW'*GW+T'*T)\GW';
GCV=(ndata*(L2^2))/(trace(eye(size(GW*Gsharp))-GW*Gsharp)^2);
%Get Akaike
Ms=max(size(T));
N=max(size(S));
Nhp=2;
phi=(ndata+Ms-N);
ABIC=phi*log10(2*pi)+phi*log10(L2^2+LS^2)-2*Ms*log10(lambda)+2*phi*log10(phi)+log10(norm(GW'*GW+T'*T,2))+phi+2*Nhp;
%Now split into GPS and wave gauge metrics
VRgps=sum((U_gps-Uforward_gps).^2)/sum(U_gps.^2);
VRgps=(1-VRgps)*100;
RMSwv=(sum((Uforward_wv-U_wv).^2)/length(Uforward_wv)).^0.5;
%Sea floor displacements
USF=GSF*S;
%Split into strike-slip and dip-slip to compute rake etc.
for i = 1:length(xs)
    S1(i,1)=S((i-1)*2+1)*1000;
    S2(i,1)=S((i-1)*2+2)*1000;
end
ST = (S1.^2+S2.^2).^0.5./1000; %Strike
Mo = sum(30e9.*ST.*area.*1000.*1000)/1e-7;
Mw=(2/3)*log10(Mo)-10.7;
Mo=Mo/1e7;
%And rake
sigma=-(strike-180); %Angle the dipslip vector points to (clockwise is negative) with respect to horizontal
theta=rad2deg(-atan(S1./S2)); %Angle teh slip vector makes in the ss,ds reference frame (clockwise is negative)
rake_h=sigma+theta; %Angle the slip vector make with respect tot eh horizontal due East (clockwise is engative)
fact=5;
rake_amp=ones(size(rake_h))/fact;%sqrt(S1.^2+S2.^2)/fact;
%Output variables
varargout{1}=lambda;
varargout{2}=L2;
varargout{3}=LS;
varargout{4}=Mo;
varargout{5}=Mw;
varargout{6}=GCV;
varargout{7}=ABIC;
varargout{8}=VRgps;
varargout{9}=RMSwv;

%Write model results
fid=fopen([outpath runName '.' runID '.slip'],'wt');
fid2=fopen([outpath runName '.' runID '.disp'],'wt');
fid3=fopen([outpath runName '.' runID '.sflr'],'wt');
fid4=fopen([outpath runName '.' runID '.dtopo'],'wt');
fid5=fopen([outpath runName '.' runID '.rake'],'wt');
fid6=fopen([outpath runName '.' runID '.wave'],'wt');
for i=1:length(xs)
    fprintf(fid,'%1.0f %1.0f %1.5f %1.5f %1.2f %1.5f %1.5f %1.5f\n',k,i,S1(i),S2(i),Mw,xs(i),ys(i),zs(i));
end
nnn = 1;
%Write displacements, observed and synthetic
for i=1:length(site)
    siter = site(i);
    siterb=num2str(siter);
    fprintf(fid2,'%s %1.0f %1.4f %1.4f %1.4f %1.4f %1.4f %1.4f %1.4f %1.4f\n',siterb,k,latinv(i),loninv(i),U((nnn-1)*3+2),...
        U((nnn-1)*3+1),U((nnn-1)*3+3),Uforward((nnn-1)*3+2),Uforward((nnn-1)*3+1),Uforward((nnn-1)*3+3));
    nnn = nnn+1;
end
%Write  3 component synthetic seafloor displacements
nnn=1;
for i=1:length(lonsf)
    siter = i;
    siterb=num2str(siter);
    fprintf(fid3,'%s %1.0f %1.4f %1.4f %1.4f %1.4f %1.4f\n',siterb,k,latsf(i),lonsf(i),USF((nnn-1)*3+2),USF((nnn-1)*3+1),USF((nnn-1)*3+3));
    nnn = nnn+1;
end
%Write  GeoClaw dtopo type 3 file
for i=1:length(lonsf)
    fprintf(fid4,'%1.0f %1.4f %1.4f %1.4f\n',0,lonsf(i),latsf(i),0);
end
nnn=1;
for i=1:length(lonsf)
    fprintf(fid4,'%1.0f %1.4f %1.4f %1.4f\n',1,lonsf(i),latsf(i),USF((nnn-1)*3+3));
    nnn = nnn+1;
end
%Write rake vector information
for i=1:length(xs)
    
    fprintf(fid5,'%1.4f %1.4f %1.4f %1.4f\n',xs(i),ys(i),rake_h(i),rake_amp(i));
end
%Write wave gauges, observed and synthetic time,observed,synthetic
nnn=1;
for i=1:length(t_gauges)
    fprintf(fid6,'%1.4f %1.4f %1.4f\n',t_gauges(i),U((3*ngps)+i),Uforward((3*ngps)+i));
end
fclose(fid);
fclose(fid2);
fclose(fid3);
fclose(fid4);
fclose(fid5);

%Output to screen
display(['   lambda = ' num2str(lambda)])
display(['   VRgps = ' num2str(VRgps) '%'])
display(['   RMSwv = ' num2str(RMSwv) ''])
display(['   || LM || = ' num2str(LS)])
display(['   GCV = ' num2str(GCV)])
display(['   ABIC = ' num2str(ABIC)])
display(['   Mw = ' num2str(Mw)])