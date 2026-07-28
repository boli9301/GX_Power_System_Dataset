%%Test system dcopf analysis
clc;clear;
tic;

%% input data
data = load('input.mat');

%structure parameters
Num_BUS = size(data.bus,1);
Num_Branch = size(data.branch,1);
Num_G = size(data.gen,1);
Num_T = 24;
Num_day = 1;
heating_day = [1:60, 335:365];
non_heating_day = setdiff(1:365, heating_day);
%gen parameters
zone = data.gen(:,2);
state = data.gen(:,34);
Pmax = data.gen(:,10);
Pmin = data.gen(:,11);
Ramp = data.gen(:,25).*Pmax; 
Ton = data.gen(:,23);
Toff = data.gen(:,24);
a = data.gencost(:,6);
b = data.gencost(:,7);
c = data.gencost(:,8);
cost_on = data.gencost(:,3);
cost_off = data.gencost(:,4);
heat = data.gen(:,27);
H_op = data.gen(:,28);
%transmission lines paremeters
fbus=data.branch(:,1);
tbus=data.branch(:,2);
lb_trans = -data.branch(:,6);
ub_trans = data.branch(:,6); 
brch_type = data.branch(:,16);
mpc = ext2int(data.mpc);
[Cf,Ct,Cft]=makeCmatrix(mpc);
%PTDF=makePTDF(data.mpc);
tran_cost = data.branch(:,14);
tran_loss = data.branch(:,15);
%gen index
ind_coal = find(data.gen(:, 29) == 1);
ind_gas = find(data.gen(:, 29) == 2);
ind_bio = find(data.gen(:, 29) == 3);
ind_hydro = find(data.gen(:, 29) == 4);
ind_nuclear = find(data.gen(:, 29) == 5);
ind_PV = find(data.gen(:, 29) == 6);
ind_wind = find(data.gen(:, 29) == 7);
ind_line = find(data.gen(:, 29) == 8);
ind_phs = find(data.gen(:, 29) == 9);
ind_bs = find(data.gen(:, 29) == 10); 

%load
Load = data.Load';
P_load0 = Load(:,1:Num_T*Num_day);
P_load = reshape(P_load0, [Num_BUS, Num_T, Num_day]);
output = data.output_series';
output_data  = output(:,1:Num_T*Num_day);
output_data = reshape(output_data, [Num_G, Num_T, Num_day]);
%initial
lb_hydro=[];
ub_hydro=[];
ub_PV=[];
ub_wind=[];
lb_line = [];
ub_line = [];
%cost
LoadCurt_cost=10000;%load shedding
spinning_cost=2.1;%backup
%gen power output settings
ratio_hydro_min = 0.5;%hydro min power output ratio
ratio_nuclear_lb = 0.8;%nuclear min power output ratio
ratio_nuclear_ub = 0.95;%nuclear max power output ratio
Num_coal_g=size(ind_coal,1);%coal-fired numbers

%backup parameters
ratio_P_load=0.05;%load backup
ratio_new_energy=0.03;%RES backup

%storage parameters
Num_ES =size(ind_bs,1)+size(ind_phs,1);
initial_soc=0.6;
end_soc=0.6;
deta_t = 1; 
eff_char        = 0.9;
eff_dischar     = 0.9;
BuildESCap      = data.gen([ind_phs;ind_bs],10)*2;
BuildESEn       = BuildESCap * Num_T;

sub_bus = find(data.bus(:,14)==1);
con_bus = find(data.bus(:,14)==2);
gen_bus = find(data.bus(:,14)==3);
%% initial parallel
CoreNum=16; %CPU core Number 
if isempty(gcp('nocreate'))
    parpool(CoreNum);
end

%% parfor for days results
results = repmat(struct('U', [], 'S', [], 'D', [], 'Pg', [], 'Hg', [], 'PG', [], ...
    'P_brch', [], 'LoadCurt', [], 'totalcost', []), 1, Num_day);
target_days = 1:Num_day;

parfor idx = 1:Num_day
    if ismember(idx, target_days)
    hour = mod(idx - 1, Num_T) + 1;
    day = floor((idx - 1) / Num_T) + 1;
    [U, S, D, Pg, PG, P_brch, LoadCurt, totalcost, pencost, result,P_charge,P_discharge,State_of_Charge,Pcharge,Pdischarge,SpinningReservesUp,SpinningReservesDown,branchcost,spinningcost] = calculateDailyResults(day, hour, data, zone, ...
    Pmax, Pmin, Ramp, Ton, Toff, a, b, c, cost_on, cost_off, lb_trans, ub_trans, ...
    P_load, output_data, ind_coal, ind_gas, ind_bio, ind_hydro, ind_nuclear, ind_PV, ind_wind, ind_line, ind_phs, ind_bs, Cf, Ct, Cft, ...
    Num_BUS, Num_Branch, Num_G, Num_T, Num_ES, Num_day, idx,ratio_hydro_min, ...
    ratio_nuclear_lb,ratio_nuclear_ub,Num_coal_g, ratio_P_load, ...
    ratio_new_energy,LoadCurt_cost,initial_soc,end_soc,deta_t,eff_char,eff_dischar, ...
    BuildESCap,BuildESEn, spinning_cost,brch_type, fbus,tbus, ...
    heat, heating_day,non_heating_day, tran_cost, tran_loss, sub_bus, con_bus, gen_bus, H_op);
    results(idx).U = value(U); 
    results(idx).S = value(S);
    results(idx).D = value(D);
    results(idx).Pg = value(Pg);
    results(idx).PG = value(PG);
    results(idx).pencost=value(pencost);
    results(idx).P_brch = value(P_brch);
    results(idx).LoadCurt = value(LoadCurt);
    results(idx).totalcost = value(totalcost);
    results(idx).Pcharge = value(Pcharge);
    results(idx).Pdischarge = value(Pdischarge);
    results(idx).P_charge = value(P_charge);
    results(idx).P_discharge = value(P_discharge);
    results(idx).State_of_Charge = value(State_of_Charge);
    results(idx).branchcost = value(branchcost);
    results(idx).spinningcost = value(spinningcost);
    results(idx).SpinningReservesUp = value(SpinningReservesUp);
    results(idx).SpinningReservesDown = value(SpinningReservesDown);
    end
end

for i = 1:length(target_days)
    idx = target_days(i);
    U(:, :, i) = results(idx).U;
    S(:, :, i) = results(idx).S;
    D(:, :, i) = results(idx).D;
    Pg(:, :, i) = results(idx).Pg;
    PG(:, :, i) = results(idx).PG;
    P_brch(:, :, i) = results(idx).P_brch;
    LoadCurt(:, :, i) = results(idx).LoadCurt;
    pencost(i) = results(idx).pencost;
    totalcost(i) = results(idx).totalcost;
    P_charge(:,:,i) = results(idx).P_charge;
    P_discharge(:,:,i) = results(idx).P_discharge;
    State_of_Charge(:,:,i) = results(idx).State_of_Charge;
end

U_flat = reshape(U, [Num_G, Num_T * length(target_days)]);
S_flat = reshape(S, [Num_G, Num_T * length(target_days)]);
D_flat = reshape(D, [Num_G, Num_T * length(target_days)]);
Pg_flat = reshape(Pg, [Num_G, Num_T * length(target_days)]);
PG_flat = reshape(PG, [Num_BUS, Num_T * length(target_days)]);
P_brch_flat = reshape(P_brch, [Num_Branch, Num_T * length(target_days)]);
LoadCurt_flat = reshape(LoadCurt, [Num_BUS, Num_T * length(target_days)]);
P_load_flat = reshape(P_load(:, :, target_days), [Num_BUS, Num_T * length(target_days)]);
P_charge_flat = reshape(P_charge, [Num_BUS, Num_T * length(target_days)]);
P_discharge_flat = reshape(P_discharge, [Num_BUS, Num_T * length(target_days)]);
State_of_Charge_flat = reshape(State_of_Charge, [Num_ES, Num_T * length(target_days)]);
delete(gcp('nocreate'));


%% total power output of each generation-tech
Pg_coal = sum(Pg_flat(ind_coal, :)); 
Pg_gas = sum(Pg_flat(ind_gas, :));
Pg_bio = sum(Pg_flat(ind_bio, :));
Pg_hydro = sum(Pg_flat(ind_hydro, :));
Pg_nuclear = sum(Pg_flat(ind_nuclear, :));
Pg_PV = sum(Pg_flat(ind_PV, :));
Pg_wind = sum(Pg_flat(ind_wind, :));
Pg_line = sum(Pg_flat(ind_line, :));
Pload = sum(P_load_flat, 1);
LoadCurt_sum = sum(LoadCurt_flat, 1);
P_discharge_sum = sum(P_discharge_flat, 1);

%% power output of each state
max_units = max(cellfun(@length, num2cell(find(zone == 1:Num_BUS))));
ind_state = zeros(Num_BUS, max_units);
PG_SUM = zeros(Num_BUS, Num_T * length(target_days));
Pload_SUM = zeros(Num_BUS, Num_T * length(target_days));

% state index
for i = 1:Num_BUS
    ind_state(i, 1:length(find(zone == data.bus(i,1)))) = find(zone == data.bus(i,1));
    PG_SUM(i, :) = sum(PG_flat(i, :), 1);
    Pload_SUM(i, :) = P_load_flat(i, :);
end
%% Visualization
figure;
bar((PG_flat+P_discharge_flat)','stack')
legendLabels = cell(1, size(sub_bus,1));
for i = 1:size(sub_bus,1)
    legendLabels{i} = ['state' num2str(i)];
end
legend(legendLabels);
title('power generation of each state at each time')

figure;
time=1:Num_T*length(target_days);
tt=[Pg_coal;Pg_gas;Pg_bio;Pg_hydro;Pg_nuclear;Pg_PV;Pg_wind;Pg_line;P_discharge_sum;LoadCurt_sum];
bar(tt','stack')
hold on;
plot(time, Pload, 'k');
legend('coal','ng','bio','hydro','nuclear','PV','wind','out lines','storage','load shedding','load')
xlabel('time')
ylabel('power')
title('power generation of each generation_tech and load at each time')

figure;
time=1:Num_T*length(target_days);
plot(time, Pg_coal, 'k', 'LineWidth', 2); 
hold on;
plot(time, Pg_gas, 'm', 'LineWidth', 2); 
hold on;
plot(time, Pg_bio, 'c', 'LineWidth', 2); 
hold on;
plot(time, Pg_hydro, 'b', 'LineWidth', 2);
hold on;
plot(time, Pg_nuclear, 'r', 'LineWidth', 2); 
hold on;
plot(time, Pg_PV, 'y', 'LineWidth', 2); 
hold on;
plot(time, Pg_wind, 'g', 'LineWidth', 2);
hold on;
plot(time, Pg_line, 'k', 'LineWidth', 2);
hold on;
plot(time,P_discharge_flat,'m', 'LineWidth', 2);
xlabel('Time (hours)');
ylabel('Power Output (MW)');
legend('Coal', 'Gas', 'Biomass', 'Hydro', 'Nuclear', 'PV', 'Wind', 'out lines','SOC');
title('power generation profiles at each time');
grid on;

%% generation structure of each state
    Pg_coal_province=zeros(Num_BUS,length(target_days)*Num_T);
    Pg_gas_province=zeros(Num_BUS,length(target_days)*Num_T);
    Pg_bio_province=zeros(Num_BUS,length(target_days)*Num_T);
    Pg_hydro_province=zeros(Num_BUS,length(target_days)*Num_T);
    Pg_nuclear_province=zeros(Num_BUS,length(target_days)*Num_T);
    Pg_PV_province=zeros(Num_BUS,length(target_days)*Num_T);
    Pg_wind_province=zeros(Num_BUS,length(target_days)*Num_T);
    Pg_line_province=zeros(Num_BUS,length(target_days)*Num_T);
    SOC=zeros(Num_BUS,length(target_days)*Num_T);
    Pr_brch=zeros(Num_BUS,length(target_days)*Num_T);
    Ps_brch=zeros(Num_BUS,length(target_days)*Num_T);
for i = 1:Num_BUS
    figure;
    
    ind_coal_province = ind_coal(ismember(ind_coal, ind_state(i,:)));
    ind_gas_province = ind_gas(ismember(ind_gas, ind_state(i,:)));
    ind_bio_province = ind_bio(ismember(ind_bio, ind_state(i,:)));
    ind_hydro_province = ind_hydro(ismember(ind_hydro, ind_state(i,:)));
    ind_nuclear_province = ind_nuclear(ismember(ind_nuclear, ind_state(i,:)));
    ind_PV_province = ind_PV(ismember(ind_PV, ind_state(i,:)));
    ind_wind_province = ind_wind(ismember(ind_wind, ind_state(i,:)));
    ind_line_province = ind_line(ismember(ind_line, ind_state(i,:)));

    Pg_coal_province(i,:) = sum(Pg_flat(ind_coal_province, :), 1);
    Pg_gas_province(i,:) = sum(Pg_flat(ind_gas_province, :), 1);
    Pg_bio_province(i,:) = sum(Pg_flat(ind_bio_province, :), 1);
    Pg_hydro_province(i,:) = sum(Pg_flat(ind_hydro_province, :), 1);
    Pg_nuclear_province(i,:) = sum(Pg_flat(ind_nuclear_province, :), 1);
    Pg_PV_province(i,:) = sum(Pg_flat(ind_PV_province, :), 1);
    Pg_wind_province(i,:) = sum(Pg_flat(ind_wind_province, :), 1);
    Pg_line_province(i,:) = sum(Pg_flat(ind_line_province, :), 1);
    SOC(i,:) = P_discharge_flat(i,:);
    
    index = find(data.branch(:,2) == data.bus(i,1));
    if size(index,1)>0
       Pr_brch(i,:) = sum(P_brch_flat(index,:),1);
    elseif size(index,1)==0
    end
    index = find(data.branch(:,1) == data.bus(i,1));
    if size(index,1)>0
       Ps_brch(i,:) = sum(P_brch_flat(index,:),1);
    elseif size(index,1)==0
    end
    gd = [Pg_coal_province(i,:); Pg_gas_province(i,:);Pg_bio_province(i,:);Pg_hydro_province(i,:); Pg_nuclear_province(i,:); Pg_PV_province(i,:); Pg_wind_province(i,:); Pg_line_province(i,:); SOC(i,:); Pr_brch(i,:); -Ps_brch(i,:)];
    bar(gd', 'stack');
    hold on
    plot(P_load_flat(i,:),'k')
    legendLabels = {'coal', 'ng', 'bio', 'hydro', 'nuclear', 'pv', 'wind', 'line', 'SOC', 'power in', 'power out', 'load'};
    legend(legendLabels);
    xlabel('time');
    ylabel('power');
    NAME = {'subC1_1', 'subC1_2', 'subC1_3', 'subC1_4', 'subC1_5', 'subC1_6', 'subC1_7', 'subC1_8', 'subC1_9', 'subC3_1', 'subC3_2', 'subC3_3', 'subC3_4', 'subC9_1', 'subC9_2'... 
        'subC9_3', 'subC9_4', 'subC11_1', 'subC11_2', 'subC11_3', 'subC11_4', 'subC11_5', 'subC11_6', 'subC11_7', 'subC11_8', 'subC4_1', 'subC4_2', 'subC12_1'... 
        'subC12_2', 'subC10_1','subC10_2','subC10_3','subC10_4','subC10_5', 'subC10_6', 'subC14_1','subC14_2', 'subC14_3', 'subC14_4', 'subC13_1', 'subC13_2', 'subC13_3', 'subC13_4', 'subC8_1', 'subC8_2', 'subC6_1'...
        'subC6_2', 'subC6_3', 'subC6_4', 'subC6_5', 'subC6_6', 'subC6_7', 'subC6_8', 'subC2_1', 'subC5_1', 'subC5_2', 'subC5_3', 'subC7_1', 'subC7_2', 'subC7_3', 'subC7_4', 'gen_hydro1', 'gen_hydro2'...
        'gen_nuclear', 'gen_coal1', 'gen_coal2',};
    title([NAME{i} 'power generation structure']);
end