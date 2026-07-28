%% The code is designed for integrating the data from the file '/Data'.
%% The economic dispatch code can use the integrated data as input.
tic;
mpc = caseGXPS_netMAX;
bus = xlsread('GXbus.xlsx','netMAX'); %BUS
gen = xlsread("GXgen.xlsx", 'netMAX');%generation units
branch = xlsread("GXbranch.xlsx", 'ACtest');%branch
gencost = xlsread("GXgencost.xlsx");%power generation costs
timeseries = xlsread("timeseries.xlsx", 'sheet1');%time-series
Load = xlsread("GXload.xlsx", 'sheet1');%load time-series

bus = bus(:,1:14);
output_series = timeseries;
output_series = output_series(2:1359,:)';
toc;