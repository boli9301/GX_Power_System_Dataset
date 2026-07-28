mpc = caseSPPS_netMIN;
mpc = toggle_dcline(mpc, 'on');          % energied DC lines

mpc.dcline(1, 4) = 3000;                 % power
mpc.dcline(1, 8)  = 1.0;                 % VF
mpc.dcline(1, 9)  = 1.0;                 % VT
mpc.dcline(2, 4) = 3000;                 % power
mpc.dcline(2, 8)  = 1.0;                 % VF
mpc.dcline(2, 9)  = 1.0;                 % VT
results = runpf(mpc);

if results.success
    disp('DC pf result:');
    disp(results.dcline);
else
    disp('infeasible');
end