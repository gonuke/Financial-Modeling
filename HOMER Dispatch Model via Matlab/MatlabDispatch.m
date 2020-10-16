% setting: 1 generator(ac), 1 pv(dc), 1 battery(dc), 1 electric load(ac)
% see definition of variables here: https://www.homerenergy.com/products/pro/docs/latest/_listing_of_simulationstate.html


function [simulation_state, matlab_simulation_variables] = MatlabDispatch(simulation_parameters, simulation_state, matlab_simulation_variables)
%%
%initiate an zero array for storing the output parameters, 3 rows for three choices and 14 columns for 14 variables 
      % row: option1, option2 option3
      option_1 = 1;
      option_2 = 2;
      option_3 = 3;
      % column: 
      % 1 - simulation_state.generators(1).power_setpoint
      generator_power_setpoint = 1;
      % 2 - simulation_state.converters(1).inverter_power_input
      inverter_power_input = 2;
      % 3 - simulation_state.converters(1).inverter_power_output
      inverter_power_output = 3;
      % 4 - simulation_state.converters(1).rectifier_power_input
      rectifier_power_input = 4;
      % 5 - simulation_state.converters(1).rectifier_power_output
      rectifier_power_output = 5;
      % 6 - simulation_state.batteries(1).power_setpoint
      battery_power_setpoint = 6;
      % 7 - simulation_state.primary_loads(1).load_served
      primary_load_served = 7;
      % 8 - simulation_state.ac_bus.excess_electricity
      ac_bus_excess_electricity = 8;
      % 9 - simulation_state.ac_bus.load_served
      ac_bus_load_served = 9;
      % 10 - simulation_state.ac_bus.capacity_requested
      ac_bus_capacity_requested = 10;
      % 11 - simulation_state.ac_bus.operating_capacity_served
      ac_bus_operating_capacity_served = 11;
      % 12 - simulation_state.ac_bus.unmet_load
      ac_bus_unmet_load = 12;
      % 13 - simulation_state.ac_bus.capacity_shortage
      ac_bus_capacity_shortage = 13;
      % 14 - marginal cost ($/kWh)
      marginal_cost = 14;
      
      % the matrix
      parameters = zeros(3,14);

      
% we don't have dc load in green case, set all related state variable to 0 
      simulation_state.dc_bus.capacity_shortage = 0;
      simulation_state.dc_bus.excess_electricity = 0;
      simulation_state.dc_bus.load_served = 0;
      simulation_state.dc_bus.operating_capacity_served = 0;
      simulation_state.dc_bus.unmet_load = 0;
 
% define intermediate variables that we do not want to see in model output
  battery_max_discharge_power = 0; % AC this one is unecessary since we will only compare this value with others when we don't have excess solar
  battery_max_charge_power = 0;    % DC
  generator_max_possible_output_from_load_and_battery = 0; % AC
  
% extract rectifier and inverter efficiency
  if simulation_parameters.has_battery == true
      %example code has the following two commands but I think they are
      %redundant since these two are already defined with HOMER design
      %interface
      simulation.converters(1).rectifier_efficiency = 90;
      simulation_parameters.converters(1).inverter_efficiency = 95;
      rect_efficiency = simulation_parameters.converters(1).rectifier_efficiency;
      inv_efficiency = simulation_parameters.converters(1).inverter_efficiency;
  end
  
% extract generator minimum ouput in kW
  if simulation_parameters.has_generator == true
    min_load = simulation_parameters.generators(1).minimum_load;
  end

  
%%  
% step 1: use PV first
  % extract available solar in kW
  if simulation_parameters.has_pv == true
      simulation_state.pvs(1).power_setpoint = simulation_state.pvs(1).power_available;
  end
  
  % actual power available after passing through the converters in kW
  % min(inverter capacity, solar supply*inverter efficiency)
  actual_inverted_power = min(simulation_parameters.converters(1).inverter_capacity, simulation_state.pvs(1).power_setpoint*inv_efficiency/100);  
  
  % calculate net load and excess solar in kW
  matlab_simulation_variables.net_load = max(simulation_state.ac_bus.load_requested - actual_inverted_power, 0);
  % in ac
  excess_solar_step_one = max(actual_inverted_power - simulation_state.ac_bus.load_requested, 0);
  
  % charge the battery with excess solar
  % min(battery maximum charge power, excess solar)
  simulation_state.batteries(1).power_setpoint = min(simulation_state.batteries(1).max_charge_power, excess_solar_step_one);
  battery_max_discharge_power = simulation_state.batteries(1).max_discharge_power + simulation_state.batteries(1).power_setpoint*(inv_efficiency/100);
  battery_max_charge_power = simulation_state.batteries(1).max_charge_power - simulation_state.batteries(1).power_setpoint;
  generator_max_possible_output_from_load_and_battery = matlab_simulation_variables.net_load + battery_max_charge_power/(rect_efficiency/100);
  
%%
% step 2: decide how to meet net load with remaining solar, generator and battery by marginal cost in $/kWh
   
      % marginal cost of each dispatch option
      % option 1: discharge battery to meet the net load as much as possible, use the generator to fill the remaining
          % marginal cost ($/kWh) = average cost of charging + battery wear cost + value of stored energy +(cost of using the generator + cost of unmet load)
      % option 2: ramp up the generator to follow the net load, store the excess eletricity if net load is lower than minimum output
          % marginal cost ($/kWh) = cost of using the generator + (average cost of charging + battery wear cost - value of stored energy + cost of unmet load)
      % option 3: ramp up the generator as much as possible
          % marginal cost ($/kWh) = cost of using the generator + average cost of charging + battery wear cost - value of stored energy
%%         
      % option 1
      % if we have enough storage in the battery to serve the net load
      if battery_max_discharge_power >= matlab_simulation_variables.net_load 
          % equals to - simulation_state.generators(1).power_setpoint = 0;
          parameters(option_1,generator_power_setpoint) = 0;
          % inverter output in ac bounds by net load and inverter capacity
          parameters(option_1,inverter_power_output) = ...
              min(matlab_simulation_variables.net_load, simulation_parameters.converters(1).inverter_capacity);
          % inverter input in dc adjusted by inverter efficiency
          parameters(option_1,inverter_power_input) = parameters(option_1,inverter_power_output)/(inv_efficiency/100);
          % battery net charge
          parameters(option_1,battery_power_setpoint) = ...
              simulation_state.batteries(1).power_setpoint - parameters(option_1,inverter_power_input);
          
          % rectifier input set to zero
          parameters(option_1,rectifier_power_input) = 0;
          % rectifier output set to zero
          parameters(option_1,rectifier_power_output) = 0;
          % primary load served
          parameters(option_1,primary_load_served) = ...
              parameters(option_1,inverter_power_output) + (simulation_state.ac_bus.load_requested - matlab_simulation_variables.net_load);
          % ac bus excess electricity
          parameters(option_1,ac_bus_excess_electricity) = excess_solar_step_one * inv_efficiency/100;
          % ac bus load served
          parameters(option_1,ac_bus_load_served) = parameters(option_1,primary_load_served);
          % ac bus operating capacity requested: refelect requested load reserve
          parameters(option_1,ac_bus_capacity_requested) = ...
              parameters(option_1,primary_load_served) + ...
             (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_1,primary_load_served);
          % ac bus operating capacity served: maximum capacity in ac
          parameters(option_1,ac_bus_operating_capacity_served) = ...
              simulation_state.batteries(1).max_discharge_power + actual_inverted_power;
          % ac bus unmet load
          parameters(option_1,ac_bus_unmet_load) = ...
              simulation_state.ac_bus.load_requested - parameters(option_1,primary_load_served);
          % ac bus capacity shortage
          parameters(option_1,ac_bus_capacity_shortage) = ...
              max(0,parameters(option_1,ac_bus_capacity_requested) - parameters(option_1,ac_bus_operating_capacity_served));
          
    
      else % battery is not enough to meet the load
          % inverter output in ac
          parameters(option_1,inverter_power_output) = ...
              min(battery_max_discharge_power, simulation_parameters.converters(1).inverter_capacity);
          % inverter input in dc
          parameters(option_1,inverter_power_input) = parameters(option_1,inverter_power_output)/(inv_efficiency/100);
          % battery net charge
          parameters(option_1,battery_power_setpoint) = ...
              simulation_state.batteries(1).power_setpoint - parameters(option_1,inverter_power_input);
          % remaining load after battery discharge to the maximum level
          remaining_load = matlab_simulation_variables.net_load - parameters(option_1,inverter_power_output);
          
          if remaining_load > min_load % we run generator at either remaining load or full capacity
             % generator output: minimum of remaining load and generator capacity
             parameters(option_1,generator_power_setpoint) = ...
                 min(remaining_load, simulation_state.generators(1).power_available);
             % rectifier input set to zero
             parameters(option_1,rectifier_power_input) = 0;
             % rectifier output set to zero
             parameters(option_1,rectifier_power_output) = 0;
             % primary load served
             parameters(option_1,primary_load_served) = ...
                 parameters(option_1,inverter_power_output) + ...
                 (simulation_state.ac_bus.load_requested - matlab_simulation_variables.net_load) + ...
                 parameters(option_1,generator_power_setpoint);
             % ac bus excess electricity
             parameters(option_1,ac_bus_excess_electricity) = excess_solar_step_one * inv_efficiency/100;
             % ac bus load served
             parameters(option_1,ac_bus_load_served) = parameters(option_1,primary_load_served);
             % ac bus operating capacity requested: reflect requested load reserve
             parameters(option_1,ac_bus_capacity_requested) = ...
                 parameters(option_1,primary_load_served) + ...
                 (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_1,primary_load_served);
             % ac bus operating capacity served: maximum capacity in ac
             parameters(option_1,ac_bus_operating_capacity_served) = ...
                 simulation_state.batteries(1).max_discharge_power + actual_inverted_power + ...
                 simulation_state.generators(1).power_available;
             % ac bus unmet load
             parameters(option_1,ac_bus_unmet_load) = ...
                 simulation_state.ac_bus.load_requested - parameters(option_1,primary_load_served);
             % ac bus capacity shortage
             parameters(option_1,ac_bus_capacity_shortage) = ...
                 max(0,parameters(option_1,ac_bus_capacity_requested) - parameters(option_1,ac_bus_operating_capacity_served));
             
          else % we run generator at min_load
             % generator output: minimum load
             parameters(option_1,generator_power_setpoint) = min_load;
             % inverter output in ac
             parameters(option_1,inverter_power_output) = ...
                 min(simulation_parameters.converters(1).inverter_capacity, ...
                 max(0, matlab_simulation_variables.net_load - parameters(option_1,generator_power_setpoint));
             % inverter input in dc
             parameters(option_1,inverter_power_input) = parameters(option_1,inverter_power_output)/(inv_efficiency/100);
             % battery net charge
             parameters(option_1,battery_power_setpoint) = ...
                 simulation_state.batteries(1).power_setpoint - parameters(option_1,inverter_power_input);
             % rectifier input
             parameters(option_1,rectifier_power_input) = ...
                 min(simulation_parameters.converters(1).rectifier_capacity,...   
                 min(battery_max_charge_power - parameters(option_1,battery_power_setpoint),...
                 parameters(option_1,generator_power_setpoint) - parameters(option_1,inverter_power_output)));
             % rectifier output
             parameters(option_1,rectifier_power_output) = parameters(option_1,rectifier_power_input)*(rect_efficiency/100);
             % battery net charge
             parameters(option_1,battery_power_setpoint) = ...
                 parameters(option_1,battery_power_setpoint) + parameters(option_1,rectifier_power_output);
             % primary load served
             parameters(option_1,primary_load_served) = ...
                 parameters(option_1,inverter_power_output) + ...
                 (simulation_state.ac_bus.load_requested - matlab_simulation_variables.net_load) + ...
                 parameters(option_1,generator_power_setpoint);
             % ac bus excess electricity
             parameters(option_1,ac_bus_excess_electricity) = ...
                 excess_solar_step_one * inv_efficiency/100 + ...
                 (parameters(option_1,inverter_power_input)==0)*...
                 (parameters(option_1,generator_power_setpoint)-matlab_simulation_variables.net_load);
             % ac bus load served
             parameters(option_1,ac_bus_load_served) = parameters(option_1,primary_load_served);
             % ac bus operating capacity requested: reflect requested load reserve
             parameters(option_1,ac_bus_capacity_requested) = ...
                 parameters(option_1,primary_load_served) + ...
                 (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_1,primary_load_served);
             % ac bus operating capacity served: maximum capacity in ac
             parameters(option_1,ac_bus_operating_capacity_served) = ...
                 simulation_state.batteries(1).max_discharge_power + actual_inverted_power + ...
                 simulation_state.generators(1).power_available;
             % ac bus unmet load
             parameters(option_1,ac_bus_unmet_load) = simulation_state.ac_bus.load_requested - parameters(option_1,primary_load_served);
             % ac bus capacity shortage
             parameters(option_1,ac_bus_capacity_shortage) = ...
                 max(0,parameters(option_1,ac_bus_capacity_requested) - parameters(option_1,ac_bus_operating_capacity_served));
             
          end
      end
   
      
 %%         
      % option 2
      % if net load is lower than min load, we run generator at min load
      if matlab_simulation_variables.net_load <= min_load
          % generator output: minimum load
          parameters(option_2,generator_power_setpoint) = min_load;  
          % use the remaining to charge battery
          excess_generator_output = parameters(option_2,generator_power_setpoint) - matlab_simulation_variables.net_load;
          % do we have enough place to store all excess electricity
          if excess_generator_output >= battery_max_charge_power/(rect_efficiency/100)
              % rectifier output: bound by remaining charging power and rectifier capacity
              parameters(option_2,rectifier_power_output) = ...
                  min(battery_max_charge_power/(rect_efficiency/100), simulation_parameters.converters(1).rectifier_capacity);
          else % we can actually store all excess power into battery if remaining charging power allows
              % rectifier output: excess output and rectifier capacity
              parameters(option_2,rectifier_power_output) = ...
                  min(excess_generator_output, simulation_parameters.converters(1).rectifier_capacity);
          end
              % rectifier input
              parameters(option_2,rectifier_power_input) = parameters(option_2,rectifier_power_output)/(rect_efficiency/100);
              % battery net charge
              parameters(option_2,battery_power_setpoint) = ...
                  parameters(option_2,rectifier_power_output) + simulation_state.batteries(1).power_setpoint;
              % inverter input set to 0
              parameters(option_2,inverter_power_input) = 0;
              % inverter output set to 0
              parameters(option_2,inverter_power_output) = 0;
              % primary load served
              parameters(option_2,primary_load_served) = simulation_state.ac_bus.load_requested;
              % ac bus excess electricity
              parameters(option_2,ac_bus_excess_electricity) = ...
                  excess_solar_step_one * inv_efficiency/100 + excess_generator_output- parameters(option_2,rectifier_power_input);
              % ac bus load served
              parameters(option_2,ac_bus_load_served) = parameters(option_2,primary_load_served);
              % ac bus operating capacity requested
              parameters(option_2,ac_bus_capacity_requested) = ...
                  parameters(option_2,primary_load_served) + ...
                  (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_2,primary_load_served);
              % ac bus operating capacity served
              parameters(option_2,ac_bus_operating_capacity_served) = ...
                  simulation_state.batteries(1).max_discharge_power + actual_inverted_power + simulation_state.generators(1).power_available;
              % as bus unmet load
              parameters(option_2,ac_bus_unmet_load) = simulation_state.ac_bus.load_requested - parameters(option_2,primary_load_served);
              % ac bus capacity shortage
              parameters(option_2,ac_bus_capacity_shortage) = ...
                  parameters(option_2,ac_bus_capacity_requested) - parameters(option_2,ac_bus_operating_capacity_served);
            
      else % if net load larger than min load, we run generator at either net load or full capacity
          % generator output: minimum load
          parameters(option_2,generator_power_setpoint) = ...
              min(matlab_simulation_variables.net_load, simulation_state.generators(1).power_available);   
          % do we have unmet load here
          unmet_load = max(0, matlab_simulation_variables.net_load - simulation_state.generators(1).power_available);
          % discharge the battery to meet this unmet load if possible
          % inverter output
          parameters(option_2,inverter_power_output) = min(unmet_load, battery_max_discharge_power);
          % inverter input
          parameters(option_2,inverter_power_input) = parameters(option_2,inverter_power_output)/(inv_efficiency/100);
          % rectifier output: 0
          parameters(option_2,rectifier_power_output) = 0;
          % rectifier input
          parameters(option_2,rectifier_power_input) = 0;
          % battery net charge
          parameters(option_2,battery_power_setpoint) = ...
              - parameters(option_2,inverter_power_input) + simulation_state.batteries(1).power_setpoint;
          % primary load served
          parameters(option_2,primary_load_served) = parameters(option_2,generator_power_setpoint) + parameters(option_2,inverter_power_output);
          % ac bus excess electricity
          parameters(option_2,ac_bus_excess_electricity) = excess_solar_step_one * inv_efficiency/100;
          % ac bus load served
          parameters(option_2,ac_bus_load_served) = parameters(option_2,primary_load_served);
          % ac bus operating capacity requested
          parameters(option_2,ac_bus_capacity_requested) = ...
              parameters(option_2,primary_load_served) + ...
              (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_2,primary_load_served);
          % ac bus operating capacity served
          parameters(option_2,ac_bus_operating_capacity_served) = ...
              simulation_state.batteries(1).max_discharge_power + actual_inverted_power + ...
              simulation_state.generators(1).power_available;
          % as bus unmet load
          parameters(option_2,ac_bus_unmet_load) = simulation_state.ac_bus.load_requested - parameters(option_2,primary_load_served);
          % ac bus capacity shortage
          parameters(option_2,ac_bus_capacity_shortage) = ...
              parameters(option_2,ac_bus_capacity_requested) - parameters(option_2,ac_bus_operating_capacity_served);

      end
          
%%          
      % option 3
      
      if generator_max_possible_output_from_load_and_battery <= min_load
          % inverter input: 0
          parameters(option_3,inverter_power_input) = 0;
          % inverter output: 0
          parameters(option_3,inverter_power_output) = 0;
          % generator output: minimum load
          parameters(option_3,generator_power_setpoint) = min_load;
          % use the remaining to charge battery
          excess_generator_output = parameters(option_3,generator_power_setpoint) - matlab_simulation_variables.net_load;
          % do we have enough space in battery
          if excess_generator_output >= (battery_max_charge_power/(rect_efficiency/100))
              % rectifier output
              parameters(option_3,rectifier_power_output) = ...
                  min(battery_max_charge_power/(rect_efficiency/100), simulation_parameters.converters(1).rectifier_capacity);
          else
              % rectifier output
              parameters(option_3,rectifier_power_output) = ...
                  min(excess_generator_output, simulation_parameters.converters(1).rectifier_capacity);
          end

      else % we run generator either at full capacity or maximum possible output considering battery
          % generator output: minimum load
          parameters(option_3,generator_power_setpoint) = ...
              min(generator_max_possible_output_from_load_and_battery, simulation_state.generators(1).power_available);    
          % if we have unmet load, discharge battery to meet the remaining if possible
          remain_load = max(0,matlab_simulation_variables.net_load - parameters(option_3,generator_power_setpoint));
          if remain_load>0 % we run generator at full capacity with battery assistance, this is equal to option 2
            % inverter output
            parameters(option_3,inverter_power_output) = min(remain_load, battery_max_discharge_power);
            % inverter input
            parameters(option_3,inverter_power_input) = parameters(option_3,inverter_power_output)/(inv_efficiency/100);
            % rectifier output: 0
            parameters(option_3,rectifier_power_output) = 0;
            % rectifier input
            parameters(option_3,rectifier_power_input) = 0;
            % battery net charge
            parameters(option_3,battery_power_setpoint) = ...
                - parameters(option_3,inverter_power_input) + simulation_state.batteries(1).power_setpoint;
            % primary load served
            parameters(option_3,primary_load_served) = ...
                parameters(option_3,generator_power_setpoint) + parameters(option_3,inverter_power_output);
            % ac bus excess electricity
            parameters(option_3,ac_bus_excess_electricity) = excess_solar_step_one * inv_efficiency/100;

          else
              % inverter input: 0
              parameters(option_3,inverter_power_input) = 0;
              % inverter output: 0
              parameters(option_3,inverter_power_output) = 0;
              % use the remaining to charge battery
              excess_generator_output = parameters(option_3,generator_power_setpoint) - matlab_simulation_variables.net_load;
              % rectifier output
              parameters(option_3,rectifier_power_output) = ...
                  min(excess_generator_output, simulation_parameters.converters(1).rectifier_capacity); 
              % rectifier input
              parameters(option_3,rectifier_power_input) = parameters(option_3,rectifier_power_output)/(rect_efficiency/100);
              % battery net charge
              parameters(option_3,battery_power_setpoint) = ...
                  simulation_state.batteries(1).power_setpoint + parameters(option_3,rectifier_power_input);
              % primary load served
              parameters(option_3,primary_load_served) = simulation_state.ac_bus.load_requested;
              % ac bus excess electricity
              parameters(option_3,ac_bus_excess_electricity) = ...
                  excess_solar_step_one * inv_efficiency/100 + excess_generator_output - parameters(option_3,rectifier_power_input); 
 
          end
         
          % ac bus load served
          parameters(option_3,ac_bus_load_served) = parameters(option_3,primary_load_served);
          % ac bus operating capacity requested
          parameters(option_3,ac_bus_capacity_requested) = ...
              parameters(option_3,primary_load_served) + ...
              (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_3,primary_load_served);
          % ac bus operating capacity served
          parameters(option_3,ac_bus_operating_capacity_served) = ...
              actual_inverted_power + simulation_state.generators(1).power_available;
          % as bus unmet load
          parameters(option_3,ac_bus_unmet_load) = ...
              simulation_state.ac_bus.load_requested - parameters(option_3,primary_load_served);
          % ac bus capacity shortage
          parameters(option_3,ac_bus_capacity_shortage) = ...
              parameters(option_3,ac_bus_capacity_requested) - parameters(option_3,ac_bus_operating_capacity_served);  
  
      end
      
 %%
 
 % costs
parameters(:,marginal_cost) = ...
    % if generator is turned on, calculate fuel cost
    matlab_simulation_variables.generator_fuel_cost * parameters(:,generator_power_setpoint)/matlab_simulation_variables.net_load ...
    % if generator is turned on, calculate O&M cost
    + (parameters(:,generator_power_setpoint)>0) * matlab_simulation_variables.generator_OM / matlab_simulation_variables.net_load ...
    
    % if battery is discharged, calculate the fuel cost of stored energy
    + simulation_state.batteries(1).energy_cost * parameters(:,inverter_power_output)/matlab_simulation_variables.net_load ...
    % if battery is discharged, calculate the battery wear cost of discharging
    + simulation_parameters.batteries(1).wear_cost * parameters(:,inverter_power_output)/matlab_simulation_variables.net_load ...
    % if battery is charged, calculate the battery wear cost of charging
    + simulation_parameters.batteries(1).wear_cost * parameters(:,rectifier_power_input)/matlab_simulation_variables.net_load ...
    % if battery is discharged, add on the value of stored energy
    + matlab_simulation_variables.electricity_price * parameters(:,inverter_power_output)/matlab_simulation_variables.net_load ...
    % if battery is charged, take out the value of stored energy
    - matlab_simulation_variables.electricity_price * parameters(:,rectifier_power_input)/matlab_simulation_variables.net_load ...
    
    % add on the value of unmet load if there is any
    + matlab_simulation_variables.electricity_price * parameters(:,ac_bus_unmet_load)/matlab_simulation_variables.net_load;     
 
 
    
costs = parameters(:,marginal_cost);
          
indx_min_cost = find(costs == min(costs));

% if there is a tie, always choose the one that charge the battery most
if length(indx_min_cost)>1
    indx_min_cost = max(indx_min_cost);
end

simulation_state.generators(1).power_setpoint          = parameters(indx_min_cost,generator_power_setpoint)
simulation_state.converters(1).inverter_power_input    = parameters(indx_min_cost,inverter_power_input)
simulation_state.converters(1).inverter_power_output   = parameters(indx_min_cost,inverter_power_output)
simulation_state.converters(1).rectifier_power_input   = parameters(indx_min_cost,rectifier_power_input)
simulation_state.converters(1).rectifier_power_output  = parameters(indx_min_cost,rectifier_power_output)
simulation_state.batteries(1).power_setpoint           = parameters(indx_min_cost,battery_power_setpoint)
simulation_state.primary_loads(1).load_served          = parameters(indx_min_cost,primary_load_served)
simulation_state.ac_bus.excess_electricity             = parameters(indx_min_cost,ac_bus_excess_electricity)
simulation_state.ac_bus.load_served                    = parameters(indx_min_cost,ac_bus_load_served)
simulation_state.ac_bus.load_requested                 = parameters(indx_min_cost,ac_bus_capacity_requested)
simulation_state.ac_bus.operating_capacity_served      = parameters(indx_min_cost,ac_bus_operating_capacity_served)
simulation_state.ac_bus.unmet_load                     = parameters(indx_min_cost,ac_bus_unmet_load)
simulation_state.ac_bus.capacity_shortage              = parameters(indx_min_cost,ac_bus_capacity_shortage)

          
end
      

