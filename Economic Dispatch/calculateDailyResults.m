%% SUB
function   [U, S, D, Pg, PG, P_brch, LoadCurt, totalcost, pencost, result,P_charge,P_discharge,State_of_Charge,Pcharge,Pdischarge,SpinningReservesUp,SpinningReservesDown,branchcost,spinningcost] = calculateDailyResults(day, hour, data, zone, ...
    Pmax, Pmin, Ramp, Ton, Toff, a, b, c, cost_on, cost_off, lb_trans, ub_trans, ...
    P_load, output_data, ind_coal, ind_gas, ind_bio, ind_hydro, ind_nuclear, ind_PV, ind_wind, ind_line, ind_phs, ind_bs, Cf, Ct, Cft, ...
    Num_BUS, Num_Branch, Num_G, Num_T, Num_ES, Num_day, idx,ratio_hydro_min, ...
    ratio_nuclear_lb,ratio_nuclear_ub,Num_coal_g, ratio_P_load, ...
    ratio_new_energy,LoadCurt_cost,initial_soc,end_soc,deta_t,eff_char,eff_dischar, ...
    BuildESCap,BuildESEn, spinning_cost,brch_type, fbus,tbus, ...
    heat, heating_day,non_heating_day, tran_cost, tran_loss, sub_bus, con_bus, gen_bus, H_op)

%% Variables
U=binvar(Num_G,Num_T,'full');%0/1 status
S=binvar(Num_G,Num_T,'full');%start=1
D=binvar(Num_G,Num_T,'full');%shut=1
P_brch = sdpvar(Num_Branch,Num_T,'full');%branch power
Pg=sdpvar(Num_G,Num_T,'full');%generator power
PG=sdpvar(Num_BUS,Num_T,'full');%bus power
LoadCurt = sdpvar(Num_BUS,Num_T,'full'); %load shedding
P_charge = sdpvar(Num_BUS,Num_T,'full');% bus charge power
P_discharge = sdpvar(Num_BUS,Num_T,'full');%bus discharge power
Pcharge = sdpvar(Num_ES,Num_T,'full');%bus storage power
Pdischarge = sdpvar(Num_ES,Num_T,'full');%bus storage power
%% Constraints
st1=[];
%% ------------------------generator power limits------------------%%%%
for i=1:Num_BUS
    ind_coal_area = ind_coal(find(zone(ind_coal, 1) == data.bus(i,1)));
    ind_gas_area = ind_gas(find(zone(ind_gas, 1) == data.bus(i,1)));
    ind_bio_area = ind_bio(find(zone(ind_bio, 1) == data.bus(i,1)));
    ind_area = [ind_coal_area;ind_gas_area;ind_bio_area];
    if ~isempty(ind_coal_area)
        for t = 1:Num_T
            st1=st1+(sum(U(ind_coal_area,t))>=0.5*size(ind_coal_area,1));
        end
    end
    if ~isempty([ind_coal_area;ind_gas_area;ind_bio_area])
        for t=1:Num_T
            st1=st1+(sum(U(ind_area,t))>=0.5*size(ind_area,1));
        end
    end
end
%%CHP
ind_gen = data.gen(:,1);
ind_heat = ind_gen(find(heat==1));
if ismember(idx,heating_day)
    for g = 1:Num_G
        if ismember(g,[ind_coal;ind_gas;ind_bio])
            if heat(g,1)==1
                st1=st1+(U(g,:)>=0.01);
            end
            lb_heat=U(g,:)*H_op(g,1);  
            ub_heat=U(g,:)*Pmax(g,1);
            st1=st1+(lb_heat<=Pg(g,:)<=ub_heat);
        end
    end
    for i =1:Num_BUS
        ind_heat_area = ind_heat(find(zone(ind_heat,1) == data.bus(i,1)));
        if ~isempty(ind_heat_area)
                for t=1:Num_T
                    st1=st1+(sum(U(ind_heat_area,t))>=0.6*size(ind_heat_area,1));
                end
        end
    end
end

for g=1:Num_G
    if ismember(g,[ind_coal;ind_gas;ind_bio])%%thermal power limit
        lb=U(g,:)*Pmin(g,1); 
        ub=U(g,:)*Pmax(g,1);
        st1=st1+(lb<=Pg(g,:)<=ub);
    elseif ismember(g,ind_hydro)%%hydro power limit
        lb_hydro=ratio_hydro_min*output_data(g,:,idx);
        ub_hydro=output_data(g,:,idx);
        st1=st1+(lb_hydro<=Pg(g,:)<=ub_hydro);
    elseif ismember(g,ind_nuclear)%%nuclear power limit
        lb_nuclear=ratio_nuclear_lb*Pmax(g,1);
        ub_nuclear=ratio_nuclear_ub*Pmax(g,1);
        st1=st1+(lb_nuclear<=Pg(g,:)<=ub_nuclear);
    elseif ismember(g,ind_PV)%%PV power limit
        lb_PV=Pmin(g,1);
        ub_PV=output_data(g,:,idx);
        st1=st1+(lb_PV<=Pg(g,:)<=ub_PV);
    elseif ismember(g,ind_wind)%%wind power limit
        lb_wind=Pmin(g,1);
        ub_wind=output_data(g,:,idx);
        st1=st1+(lb_wind<=Pg(g,:)<=ub_wind);
    elseif ismember(g,ind_line)
        lb_line=Pmax(g,1)*0.1;
        ub_line=Pmax(g,1)*0.5;
        st1=st1+(lb_line<=Pg(g,:)<=ub_line);
    end
end
%% ------------------------------Ramp limits------------------------
st2=[];
for g=1:Num_G
    if ismember(g,[ind_coal;ind_gas;ind_bio])
        for t=2:Num_T
            lb_RampDown=Ramp(g)+D(g,t)*Pmin(g,1);
            ub_RampUp=Ramp(g)+S(g,t)*Pmin(g,1);
            st2=st2+(Pg(g,t-1)-Pg(g,t)<=lb_RampDown);%%down
            st2=st2+(Pg(g,t)-Pg(g,t-1)<=ub_RampUp);%%up
        end
    end
end

% %% --------------------------------startup/shutdown limts--------------------------
st3=[];
%status constraints
for g=1:Num_G
    if ismember(g,[ind_coal;ind_gas;ind_bio])
        for t=2:Num_T
            st3=st3+(U(g,t)==U(g,t-1)+S(g,t)-D(g,t));
        end
    end
end
%start
for g=1:Num_G
    if ismember(g,[ind_coal;ind_gas;ind_bio])
        for t=2:Num_T
            indicator=U(g,t)-U(g,t-1);
            range=t:min(Num_T,t+Ton(g)-1);
            st3=st3+(U(g,range)>=indicator);
        end
    end
end
%shut
for g=1:Num_G
    if ismember(g,[ind_coal;ind_gas;ind_bio])
        for t=2:Num_T
            indicator=U(g,t-1)-U(g,t);
            range=t:min(Num_T,t+Toff(g)-1);
            st3=st3+(0<=U(g,range)<=1-indicator);
        end
    end
end 

%% ----------------------------------backup constraints---------------------------------
st4=[];
SpinningReservesUp = sdpvar(Num_G,Num_T,'full'); 
SpinningReservesDown = sdpvar(Num_G,Num_T,'full');
for g = 1:Num_G
    if ismember(g,[ind_PV;ind_wind])   
        st4 = st4+(SpinningReservesUp(g,:) == 0 );
    elseif ismember(g,[ind_bs;ind_phs;ind_line])
        st4 = st4+(SpinningReservesUp(g,:) == 0);
        st4 = st4+(SpinningReservesDown(g,:) == 0);
    end
end
DispatchLowerLimit = sdpvar(Num_G,Num_T,'full');
DispatchUpperLimit = sdpvar(Num_G,Num_T,'full');
for g = 1:Num_G
    if ismember(g,[ind_coal;ind_gas;ind_bio])
        DispatchLowerLimit(g,:) = Pg(g,:) - U(g,:) .* (Pmin(g,1)*ones(1,Num_T));
        DispatchUpperLimit(g,:) = U(g,:) .* (Pmax(g,1)*ones(1,Num_T)) - Pg(g,:);
    elseif ismember(g,ind_hydro)
        DispatchLowerLimit(g,:) = Pg(g,:) - (ratio_hydro_min*output_data(g,:,idx));
        DispatchUpperLimit(g,:) = output_data(g,:,idx) - Pg(g,:);
    elseif ismember(g,ind_nuclear)
        DispatchLowerLimit(g,:) = Pg(g,:) - (ratio_nuclear_lb*Pmax(g,1)*ones(1,Num_T));
        DispatchUpperLimit(g,:) = ratio_nuclear_ub*Pmax(g,1)*ones(1,Num_T) - Pg(g,:);
    elseif ismember(g,ind_wind)
        DispatchLowerLimit(g,:) = Pg(g,:) - Pmin(g,1) * ones(1,Num_T);
        DispatchUpperLimit(g,:) = output_data(g,:,idx)-Pg(g,:);     
    elseif ismember(g,ind_PV)
        DispatchLowerLimit(g,:) = Pg(g,:) - Pmin(g,1) * ones(1,Num_T);
        DispatchUpperLimit(g,:) = output_data(g,:,idx)-Pg(g,:);           
    end
end

SpinningReserveUp   = sum(SpinningReservesUp,1);
SpinningReserveDown = sum(SpinningReservesDown,1);
CommittedSpinningReserveUp   = SpinningReserveUp;
CommittedSpinningReserveDown = SpinningReserveDown;
for t=1:Num_T
    Spinning_Reserve_Up_Requirements = ratio_P_load*sum(P_load(:,t,idx))+ratio_new_energy*sum(Pg(ind_wind,t))+ratio_new_energy*sum(Pg(ind_PV,t));
    Spinning_Reserve_Down_Requirements = ratio_P_load*sum(P_load(:,t,idx))+ratio_new_energy*sum(Pg(ind_wind,t))+ratio_new_energy*sum(Pg(ind_PV,t));
    st4=st4+(Spinning_Reserve_Up_Requirements<=CommittedSpinningReserveUp(:,t)<=2*Spinning_Reserve_Up_Requirements);
    st4=st4+(Spinning_Reserve_Down_Requirements<=CommittedSpinningReserveDown(:,t)<=2*Spinning_Reserve_Down_Requirements);
    st4=st4+(0*DispatchUpperLimit(:,t) <= SpinningReservesUp(:,t) <= DispatchUpperLimit(:,t));
    st4=st4+(0*DispatchLowerLimit(:,t) <= SpinningReservesDown(:,t) <= DispatchLowerLimit(:,t));
end

%% ----------------------------------power balance limits---------------------------------
st5=[];
for i = 1:Num_BUS
    ind = find(zone([ind_coal;ind_gas;ind_bio;ind_hydro;ind_nuclear;ind_PV;ind_wind;ind_line],1) == data.bus(i,1));
    if size(ind,1)>0
        PG(i,:) = sum(Pg(ind,:),1);
    else
        PG(i,:) = zeros(1,Num_T);
    end
end
for i = 1:Num_BUS
    inde = find(data.gen([ind_phs;ind_bs],2) == data.bus(i,1));
    if size(inde,1)>0
       P_charge(i,:) = sum(Pcharge(inde,:),1);
       P_discharge(i,:) = sum(Pdischarge(inde,:),1);
    else
       P_charge(i,:) = zeros(1,Num_T);
       P_discharge(i,:) = zeros(1,Num_T);
    end
end
for t=1:Num_T
    for i = 1:Num_BUS
        if ismember(i,sub_bus)
            st5 = st5+(LoadCurt(i,t)+PG(i,t)+P_discharge(i,t)+Ct(:,i)'*(P_brch(:,t).*(ones(Num_Branch,1)-tran_loss))==P_load(i,t,idx)*1.03+P_charge(i,t)+Cf(:,i)'*P_brch(:,t));
        elseif ismember(i,con_bus)
            st5 = st5+(PG(i,t)+Ct(:,i)'*(P_brch(:,t).*(ones(Num_Branch,1)-tran_loss))==Cf(:,i)'*P_brch(:,t));
        elseif ismember(i,gen_bus)
            st5 = st5+(PG(i,t)+Ct(:,i)'*(P_brch(:,t).*(ones(Num_Branch,1)-tran_loss))==Cf(:,i)'*P_brch(:,t));
        end
    st5=st5+(LoadCurt(:,t)>=0);
    end
end


%% -----------------------------------transmission limits--------------------------------
st6 = [];
for l=1:Num_Branch
    if brch_type(l,1)==2
        st6=st6+(zeros(1,Num_T)<=P_brch(l,:)<=repmat(ub_trans(l,1),1,Num_T));
    else
        st6=st6+(repmat(lb_trans(l,1),1,Num_T)<=P_brch(l,:)<=repmat(ub_trans(l,1),1,Num_T)); 
    end
end

%% -------------------------------------storage limits------------------------------------
st7=[];
State_of_Charge = sdpvar(Num_ES,Num_T,'full');
for es=1:Num_ES
    st7=st7+(State_of_Charge(es,1)==BuildESCap(es,1)*initial_soc);
        for t=1:Num_T-1
             st7=st7+(State_of_Charge(es,t+1)==State_of_Charge(es,t)+deta_t*Pcharge(es,t)*eff_char-deta_t*Pdischarge(es,t)/eff_dischar);
             st7=st7+(0<=State_of_Charge(es,t+1)<=BuildESCap(es,1));
        end
end

for es=1:Num_ES
        st7=st7+(end_soc*BuildESCap(es,1)==State_of_Charge(es,Num_T));
end

for es=1:Num_ES
    for t=1:Num_T
            st7=st7+(0<=Pcharge(es,t)<=BuildESCap(es,1)/2);
            st7=st7+(0<=Pdischarge(es,t)<=BuildESCap(es,1)/2);
            st7=st7+(Pcharge(es,Num_T)==0);
            st7=st7+(Pdischarge(es,Num_T)==0);
    end
end

%% backup costs
spinningcost=0;
for t = 1:Num_T
    spinning = sum(SpinningReservesUp(:,t))+sum(SpinningReservesDown(:,t));
    spinningcost = spinningcost+spinning*spinning_cost;
end

%% transmission costs
branchcost=0;
for l=1:Num_Branch
     branchcost=branchcost+sum(abs(P_brch(l,:)))*tran_cost(l,1);
end

%% load shedding costs
pencost=sum(sum(LoadCurt))*LoadCurt_cost;

%% obj
totalcost=0;
for g=1:Num_G
    if ismember(g,ind_coal)
        totalcost=totalcost+a(g)*sum(Pg(g,:).^2)+sum(Pg(g,:))*b(g)+Num_T*c(g); %%operating costs
        totalcost=totalcost+sum(S(g,:)*cost_on(g));
        totalcost=totalcost+sum(D(g,:)*cost_off(g));
    elseif ismember(g,[ind_gas;ind_bio;ind_nuclear])
        totalcost = totalcost+sum(Pg(g,:))*b(g);
    end
end
totalcost=totalcost+pencost+branchcost+spinningcost;

%%  solver settings
st = [st1;st2;st3;st4;st5;st6;st7];
ops=sdpsettings('solver', 'gurobi','gurobi.MIPGap', 0.05);
% ops=sdpsettings('solver', 'cplex');
result=optimize(st,totalcost,ops);
if result.problem == 1
    disp('fail');
elseif result.problem ~= 0
    disp(['problem back: ', yalmiperror(result.problem)]);
end
double(totalcost)
end