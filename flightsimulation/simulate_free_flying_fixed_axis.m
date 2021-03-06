%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 
% Authors: Klaus Seywald (klaus.seywald@mytum.de) 
%          and Simon Binder (simon.binder@tum.de)
% 
% This file is part of dAEDalusNXT (https://github.com/seyk86/dAEDalusNXT)
%

function FixedAxis=simulate_free_flying_fixed_axis(aircraft,aircraft_structure,fixed_node,trimmed_state,ctrl_input,t_vec,dt,maneuver_name,movie_on)

mkdir(['results/' aircraft.name],maneuver_name);
mkdir(['results/' aircraft.name '/' maneuver_name],'movie');

if ctrl_input.signals.dimensions~=length(aircraft.control_surfaces)
    disp('Control Input Signal Incorrect')
end
breakevery=100;
% set newmark beta scheme parameters
beta_newmark=1/4;
gamma_newmark=1/2;
rtf=1;
% initialize flight state variables
FixedAxis.Xe=zeros(length(t_vec),3);
FixedAxis.Euler=zeros(length(t_vec),3);
FixedAxis.Vb=zeros(length(t_vec),3);
FixedAxis.Ve=zeros(length(t_vec),3);
FixedAxis.pqr=zeros(length(t_vec),3);
FixedAxis.pqr_dot=zeros(length(t_vec),3);
FixedAxis.Alpha=zeros(length(t_vec),1);
FixedAxis.Beta=zeros(length(t_vec),1);
FixedAxis.V=zeros(length(t_vec),1);
FixedAxis.qinf=zeros(length(t_vec),1);
FixedAxis.Ma=zeros(length(t_vec),1);
FixedAxis.Loads=zeros(ceil(length(t_vec)/rtf),length(aircraft_structure.Ftest));
FixedAxis.Error=zeros(length(t_vec),1);
% for testing
gravity_on=1;

% initialize state vectors to zero
x_now=zeros(length(aircraft_structure.Kff),1);
x_nxt=x_now;
xdot_now=x_now;
xdotdot_now=x_now;
xdotdot_nxt=x_now;

% initialize a-system variables
V_a = zeros(3,1);
alpha_a = 0;
beta_a = 0;
pqr_a = zeros(3,1);


xdot_now(1:6)=[-trimmed_state.aerodynamic_state.V_A 0 0 0 0 0];
xdot_now(6)=0*pi/180;
xdotdot_now(1:3)=0;
%aircraft_structure.nodal_deflections=zeros(length(aircraft_structure.Kff),1);
%aircraft_structure=aircraft_structure.f_postprocess();

% set boundary conditions
fixed_frame_bcs=[];
for n=1:length(aircraft_structure.Mff_lumped)
    if n<(fixed_node*6-5)
        fixed_frame_bcs=[fixed_frame_bcs n];
    elseif n>(fixed_node*6)
        fixed_frame_bcs=[fixed_frame_bcs n];
    end
end

[s_inertial,delta_inertial,I_Hat,b,b_Hat_Skew,omega_Hat_Skew,A_Bar]=compute_eqm_matrices(x_now(4:6),xdot_now(4:6),aircraft_structure.node_coords,aircraft_structure.nodal_deflections,fixed_node);
[M_tot_mean,K_tot_mean,F_tot_mean]=compute_fixed_axis_matrices(A_Bar,I_Hat,b,b_Hat_Skew,omega_Hat_Skew,aircraft_structure.Mff_lumped,aircraft_structure.Kff,xdot_now,fixed_frame_bcs);

% set current weight
%aircraft.weights.W=M_tot_mean(1,1);
%trimmed_state.aircraft_state.weight=M_tot_mean(1,1);

% trim & initialize aerodynamics
aircraft.grid_settings.wake=2;
aircraft=aircraft.compute_grid();

%[s_inertial,delta_inertial,I_Hat,b,b_Hat_Skew,omega_Hat_Skew,A_Bar]=compute_eqm_matrices_mean([0 0 0]',[0 0 0]',aircraft_structure.node_coords,aircraft_structure.nodal_deflections,[0 0 0]',[0 0 0]');
%mean_axis_origin=-(I_Hat'*A_Bar*aircraft_structure.Mff_lumped*A_Bar'*I_Hat)^-1*I_Hat'*(A_Bar*aircraft_structure.Mff_lumped*A_Bar'*s_inertial');

%trim_state.aircraft_state.CG_ref=-mean_axis_origin';



x_now_init=zeros(length(F_tot_mean),1);
for i=1:length(aircraft_structure.node_coords)-1
    x_now_init(7+6*(i-1):6+6*i)= aircraft_structure.nodal_deflections(fixed_frame_bcs(1+6*(i-1):6*i))-aircraft_structure.nodal_deflections(6*(fixed_node-1)+1:6*(fixed_node-1)+6).*[1 1 1 1 1 1]';
end
x_now=x_now_init;
x_now(1:6)=[0 0 1000 0 trimmed_state.aerodynamic_state.alpha*pi/180+aircraft_structure.nodal_deflections(6*(fixed_node-1)+5) 0];
zwxnxt=x_now(7:end);
x_nxt_full=zeros(length(aircraft_structure.Kff),1);
for nn=1:length(fixed_frame_bcs)
    x_nxt_full(fixed_frame_bcs(nn))=zwxnxt(nn);
end
    aircraft_structure.nodal_deflections=x_nxt_full;
    aircraft_structure=aircraft_structure.f_postprocess();
    aircraft=aircraft.compute_deflected_grid(aircraft_structure.f_get_deflections);

[s_inertial,delta_inertial,I_Hat,b,b_Hat_Skew,omega_Hat_Skew,A_Bar]=compute_eqm_matrices(x_now(4:6),xdot_now(4:6),aircraft_structure.node_coords,aircraft_structure.nodal_deflections,fixed_node);
[M_tot_mean,K_tot_mean,F_tot_mean]=compute_fixed_axis_matrices(A_Bar,I_Hat,b,b_Hat_Skew,omega_Hat_Skew,aircraft_structure.Mff_lumped,aircraft_structure.Kff,xdot_now,fixed_frame_bcs);

xdot_now(1:3)=-[norm(trimmed_state.aerodynamic_state.V_inf) 0 0];


aeroelastic_solver_settings=class_aeroelastic_solver_settings;

UVLM_settings=class_UVLM_computation_settings();
UVLM_settings.debug=0;
UVLM_settings.movie=movie_on;
UVLM_settings.wakelength_factor=1;
aircraft.reference.p_ref=trimmed_state.aerodynamic_state.p_ref;
aircraft_aero=class_UVLM_solver(aircraft.name,aircraft.grid_deflected,aircraft.is_te,aircraft.panels,trimmed_state.aerodynamic_state,aircraft.grid_wake,aircraft.panels_wake,aircraft.reference,UVLM_settings);
aircraft_aero=aircraft_aero.initialize_time_domain_solution(dt*rtf);

FixedAxis.Time=t_vec;
x_prv=x_now;
xdot_prv=xdot_now;
xdotdot_prv=xdotdot_now;
control_surface_states_0=trimmed_state.aircraft_state.control_deflections;
control_surface_states=zeros(length(aircraft.control_deflections),1);
control_surface_states_prv=control_surface_states;
rho_air=trimmed_state.aerodynamic_state.rho_air;
disp('Simulating Maneouver: ')
for i=1:length(t_vec)
    if mod(i,breakevery)==0
        disp(i)
    end
    fprintf('\b\b\b\b %03d',round(t_vec(i)/t_vec(end)*100));
    % compute flight dynamic states
    FixedAxis.Xe(i,:)=[-1 0 0;0 1 0; 0 0 -1]*x_now(1:3);
    FixedAxis.Euler(i,:)=[-1 0 0;0 1 0; 0 0 -1]*x_now(4:6);
    FixedAxis.Vb(i,:)=[-1 0 0;0 1 0; 0 0 -1]*A_Bar(1:3,1:3)'*xdot_now(1:3);
    FixedAxis.Ve(i,:)=[-1 0 0;0 1 0; 0 0 -1]*xdot_now(1:3);
    FixedAxis.pqr(i,:)=([1      sin(FixedAxis.Euler(i,1))*tan(FixedAxis.Euler(i,2))         cos(FixedAxis.Euler(i,1))*tan(FixedAxis.Euler(i,2));
                        0      cos(FixedAxis.Euler(i,1))                                   -sin(FixedAxis.Euler(i,1));
                        0      sin(FixedAxis.Euler(i,1))/cos(FixedAxis.Euler(i,2))         cos(FixedAxis.Euler(i,1))/cos(FixedAxis.Euler(i,2));]^(-1)*[-1 0 0;0 1 0; 0 0 -1]*xdot_now(4:6));
    
    FixedAxis.Alpha(i)=atan(FixedAxis.Vb(i,3)/FixedAxis.Vb(i,1));
    FixedAxis.Beta(i)=atan(-FixedAxis.Vb(i,2)/FixedAxis.Vb(i,1));
    FixedAxis.V(i)=norm(FixedAxis.Vb(i,:));
    
    % update a-system variables
    V_a(1:3) = A_Bar(1:3,1:3)'*xdot_now(1:3);
    alpha_a = atand(V_a(3)/V_a(1));
    beta_a = -atand(V_a(2)/V_a(1));
    pqr_a(1:3) = [1      sin(x_now(4))*tan(x_now(2))         cos(x_now(4))*tan(x_now(5));
                     0      cos(x_now(4))                       -sin(x_now(4));
                     0      sin(x_now(4))/cos(x_now(5))         cos(x_now(4))/cos(x_now(5));]^(-1)*xdot_now(4:6);
    
    
    if mod(i,rtf)==0
    % set control surface deflections
    control_surface_states_prv=control_surface_states;
    for n_ctrl=1:length(control_surface_states)
        control_surface_states(n_ctrl)=interp1(ctrl_input.time,ctrl_input.signals.values(:,n_ctrl),t_vec(i));
    end
    % only update if changed to previous step
    if sum(control_surface_states_prv==control_surface_states)~=length(control_surface_states)
        for n_ctrl=1:length(control_surface_states)
            aircraft=aircraft.f_set_control_surface(aircraft.control_surfaces{n_ctrl},control_surface_states(n_ctrl)+control_surface_states_0{n_ctrl});
        end
        aircraft=aircraft.compute_grid();
        aircraft=aircraft.compute_deflected_grid(aircraft_structure.f_get_deflections);
    end
    
    % solve aerodynamics for current timestep

    aircraft_aero=aircraft_aero.solve_time_domain_aerodynamics(aircraft,[0*x_now(1:3)' ([-1 0 0;0 1 0; 0 0 -1]*x_now(4:6))'],V_a(:),alpha_a,beta_a,...
        pqr_a,rho_air,i,['results/' aircraft.name '/' maneuver_name '/movie/fixed_axis']);

  
    % compute loads for structure
    % aero loads
    % for testing
    % aircraft_aero.F_body(1,:)=-sin(FixedAxis.Alpha(i)).*aircraft_aero.F_body(3,:);
    
    aircraft=aircraft.compute_beam_forces(aircraft_aero.F_body,aircraft_structure);
    for bb=1:length(aircraft_structure.beam)
        if  isa(aircraft_structure.beam(bb),'class_wing')
            aircraft_structure.beam(bb)=aircraft_structure.beam(bb).f_set_aeroloads(aircraft.wings(bb));
        end
    end
    
    % graviation
    gravity=A_Bar(1:3,1:3)'*[0 0 -9.81]'*gravity_on;
    for bb=1:length(aircraft_structure.beam)
        for be=1:length(aircraft_structure.beam(bb).beamelement)
            aircraft_structure.beam(bb).beamelement(be).ax=gravity(1);
            aircraft_structure.beam(bb).beamelement(be).ay=gravity(2);
            aircraft_structure.beam(bb).beamelement(be).az=gravity(3);
            aircraft_structure.beam(bb).update_Q=1;
        end
    end
    
    aircraft_structure=aircraft_structure.f_assemble_free(1,0);
    end
  %  for fpi=1:5
        
        [s_inertial,delta_inertial,I_Hat,b,b_Hat_Skew,omega_Hat_Skew,A_Bar]=compute_eqm_matrices(x_now(4:6),xdot_now(4:6),aircraft_structure.node_coords,aircraft_structure.nodal_deflections,fixed_node);
    %    if fpi==1
            [M_tot_mean,K_tot_mean,F_acc_mean]=compute_fixed_axis_matrices(A_Bar,I_Hat,b,b_Hat_Skew,omega_Hat_Skew,aircraft_structure.Mff_lumped,aircraft_structure.Kff,xdot_now,fixed_frame_bcs);
   %     else
    %        [~,K_tot_mean,~]=compute_fixed_axis_matrices(A_Bar,I_Hat,b,b_Hat_Skew,omega_Hat_Skew,aircraft_structure.Mff_lumped,aircraft_structure.Kff,xdot_now,fixed_frame_bcs);
  %      end
        

        % assemble
        
        % plus inertial forces
        F_tot_mean=F_acc_mean+[I_Hat'*A_Bar*aircraft_structure.Ftest;b_Hat_Skew'*A_Bar*aircraft_structure.Ftest;aircraft_structure.Ftest(fixed_frame_bcs)];
        if mod(i,rtf)==0
            FixedAxis.Loads(i/rtf,7:end)=aircraft_structure.Ftest(fixed_frame_bcs)'+F_acc_mean(7:end)';
        end
        % structural raleigh damping
        C_mean=K_tot_mean*0;
        C_mean(7:end,7:end)=K_tot_mean(7:end,7:end)*0.001+M_tot_mean(7:end,7:end)*0.001;
        
        
        err_vec=M_tot_mean*xdotdot_now+C_mean*xdot_now+K_tot_mean*x_now-F_tot_mean;
        
        
        FixedAxis.Error(i)=norm(err_vec);
        %  if FixedAxis.Error(i)>300
%         if fpi>1
%             x_now=x_prv;
%             xdot_now=xdot_prv;
%             xdotdot_now=xdotdot_prv;
%         end
        %  end
        % newmark beta scheme
        x_nxt=linsolve(M_tot_mean+beta_newmark*dt^2*K_tot_mean+gamma_newmark*dt*C_mean,beta_newmark*dt^2*F_tot_mean+M_tot_mean*x_now+dt*M_tot_mean*xdot_now+dt^2*M_tot_mean*(1/2-beta_newmark)*xdotdot_now...
            +C_mean*beta_newmark*dt^2*(gamma_newmark/(beta_newmark*dt)*x_now+(gamma_newmark/beta_newmark-1)*xdot_now+1/2*dt*(gamma_newmark/beta_newmark-2)*xdotdot_now));
        xdotdot_nxt=1/(beta_newmark*dt^2)*(x_nxt-x_now-dt*xdot_now-dt^2*(1/2-beta_newmark)*xdotdot_now);
        xdot_nxt=xdot_now+dt*((1-gamma_newmark)*xdotdot_now+gamma_newmark*xdotdot_nxt);
        %
%         x_now=x_nxt;
%         xdot_now=xdot_nxt;
%         xdotdot_now=xdotdot_nxt;
 %   end
    if mod(i,rtf)==0
    % set physical deflections in structural mesh
    zwxnxt=x_nxt(7:end);
    x_nxt_full=zeros(length(aircraft_structure.Kff),1);
    for nn=1:length(fixed_frame_bcs)
        x_nxt_full(fixed_frame_bcs(nn))=zwxnxt(nn);
    end
    
    aircraft_structure.nodal_deflections=x_nxt_full;
    aircraft_structure=aircraft_structure.f_postprocess();
    aircraft=aircraft.compute_deflected_grid(aircraft_structure.f_get_deflections);
    end
    FixedAxis.Error(i)
    
    x_now=x_nxt;
    xdot_now=xdot_nxt;
    xdotdot_now=xdotdot_nxt;
end

FixedAxis.CM=aircraft_aero.CM;
FixedAxis.CZ=aircraft_aero.CZ;
FixedAxis.CX=aircraft_aero.CX;
FixedAxis.CY=aircraft_aero.CY;
FixedAxis.CL=aircraft_aero.CL;
FixedAxis.CN=aircraft_aero.CN;
save(['results/' aircraft.name '/' maneuver_name '/Simulation_Fixed_Axis'],'FixedAxis','FixedAxis');
end