% setting: 1 generator(ac), 1 pv(dc), 1 battery(dc), 1 electric load(ac)， 1
% wind turbine
% see definition of variables here: https://www.homerenergy.com/products/pro/docs/latest/_listing_of_simulationstate.html


% goal: use renewables to shave peak demand and save fuel
% battery: bounded by remaining space, converter/inverter capacity
% generator: min load, max load, converter capacity


function [simulation_state, matlab_simulation_variables] = MatlabDispatchWindplus(simulation_parameters, simulation_state, matlab_simulation_variables)
%%
% define a small enough number to account for accuracy difference
epi = 0.00001;

% initiate an zero array for storing the output parameters, 3 rows for three choices and 14 columns for 14 variables 
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
      ac_bus_operating_capacity_requested = 10;
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
      simulation_parameters.converters(1).rectifier_efficiency = 90;
      simulation_parameters.converters(1).inverter_efficiency = 95;
      rect_efficiency = simulation_parameters.converters(1).rectifier_efficiency;
      inv_efficiency = simulation_parameters.converters(1).inverter_efficiency;
  else
      simulation_parameters.converters(1).rectifier_efficiency = 1;
      simulation_parameters.converters(1).inverter_efficiency = 1;
      rect_efficiency = simulation_parameters.converters(1).rectifier_efficiency;
      inv_efficiency = simulation_parameters.converters(1).inverter_efficiency;
  end
  
% extract generator minimum ouput in kW
  if simulation_parameters.has_generator == true
    min_load = simulation_parameters.generators(1).minimum_load;
  else 
    min_load = 0;
  end

  
%%  
% step 1: use wind first, and then PV

  % extract available wind in kW (ac)
  if simulation_parameters.has_wind_turbine == true
      simulation_state.wind_turbines(1).power_setpoint = simulation_state.wind_turbines(1).power_available;
  else
      simulation_state.wind_turbines(1).power_setpoint = 0;
  end
  % serve the load with wind
  net_load_after_wind = max(0, simulation_state.ac_bus.load_requested - simulation_state.wind_turbines(1).power_setpoint);
  excess_wind_step_one = max(0, simulation_state.wind_turbines(1).power_setpoint - simulation_state.ac_bus.load_requested);
  % charge the battery with excess wind
  if simulation_parameters.has_converter == true && simulation_parameters.has_battery == true
      if simulation_state.batteries(1).max_charge_power <= epi
          simulation_state.converters(1).rectifier_power_output = 0;
      else
          simulation_state.converters(1).rectifier_power_output = ...
              min(simulation_parameters.converters(1).rectifier_capacity, ...
              min(simulation_state.batteries(1).max_charge_power, excess_wind_step_one*(rect_efficiency/100)));
      end
      simulation_state.converters(1).rectifier_power_input = simulation_state.converters(1).rectifier_power_output/(rect_efficiency/100);
      simulation_state.batteries(1).power_setpoint = simulation_state.converters(1).rectifier_power_output;
      battery_max_discharge_power = ...
          min(simulation_parameters.converters(1).inverter_capacity, ...
          simulation_state.batteries(1).max_discharge_power + simulation_state.batteries(1).power_setpoint*(inv_efficiency/100));
      battery_max_charge_power = ...
          min(simulation_parameters.converters(1).rectifier_capacity - simulation_state.converters(1).rectifier_power_output, ...
          simulation_state.batteries(1).max_charge_power - simulation_state.batteries(1).power_setpoint);
      generator_max_possible_output_from_load_and_battery = matlab_simulation_variables.net_load + battery_max_charge_power/(rect_efficiency/100);
  else
     simulation_state.batteries(1).power_setpoint = 0;
     simulation_state.converters(1).rectifier_power_input = 0;
     simulation_state.converters(1).rectifier_power_output = 0;
     battery_max_discharge_power = 0;
     battery_max_charge_power = 0;
     generator_max_possible_output_from_load_and_battery = matlab_simulation_variables.net_load;
  end
  excess_wind_step_one = excess_wind_step_one - simulation_state.converters(1).rectifier_power_input;
 
 
  
  % extract available solar in kW
  if simulation_parameters.has_pv == true
      simulation_state.pvs(1).power_setpoint = simulation_state.pvs(1).power_available;
  else
      simulation_state.pvs(1).power_setpoint = 0;
  end
  
  
  if net_load_after_wind <= epi
      simulation_state.converters(1).inverter_power_output = 0;
      simulation_state.converters(1).inverter_power_input = 0; 
      excess_solar_step_one = simulation_state.pvs(1).power_setpoint;
      % actual power available after passing through the converters in kW
      if simulation_parameters.has_converter == true
          actual_inverted_power = min(simulation_parameters.converters(1).inverter_capacity, simulation_state.pvs(1).power_setpoint*inv_efficiency/100);
      else
          actual_inverted_power = 0;
      end
      % calculate net load in kW
      matlab_simulation_variables.net_load = net_load_after_wind;
  else
      if simulation_parameters.has_converter == true
          actual_inverted_power = min(simulation_parameters.converters(1).inverter_capacity, simulation_state.pvs(1).power_setpoint*inv_efficiency/100);
          if actual_inverted_power > net_load_after_wind
              %net_load = simulation_state.ac_bus.load_requested - simulation_state.wind_turbines(1).power_setpoint;
              %simulation_state.converters(1).inverter_power_output = net_load;
              %simulation_state.converters(1).inverter_power_output = net_load_after_wind;
              %simulation_state.converters(1).inverter_power_output = 8800;
              %simulation_state.converters(1).inverter_power_output = simulation_state.ac_bus.load_requested - simulation_state.wind_turbines(1).power_setpoint +0.00001;
              simulation_state.converters(1).inverter_power_output = net_load_after_wind +0.00001;
          else
              simulation_state.converters(1).inverter_power_output = actual_inverted_power;
          end
          %simulation_state.converters(1).inverter_power_output = min(actual_inverted_power, matlab_simulation_variables.net_load);
          simulation_state.converters(1).inverter_power_input = simulation_state.converters(1).inverter_power_output / (inv_efficiency/100);
      else
          actual_inverted_power = 0;
          simulation_state.converters(1).inverter_power_output = 0;
          simulation_state.converters(1).inverter_power_input = 0;
      end
      % excess solar before charging the battery in ac
      excess_solar_step_one = simulation_state.pvs(1).power_setpoint*inv_efficiency/100 - simulation_state.converters(1).inverter_power_output;
      % calculate net load in kW
      matlab_simulation_variables.net_load = net_load_after_wind - simulation_state.converters(1).inverter_power_output;
  
      % charge the battery with excess solar
      if simulation_parameters.has_battery == true
          if battery_max_charge_power <= epi
              simulation_state.batteries(1).power_setpoint = simulation_state.batteries(1).power_setpoint;
          else
              simulation_state.batteries(1).power_setpoint = ...
                  simulation_state.batteries(1).power_setpoint + min(battery_max_charge_power, excess_solar_step_one/(inv_efficiency/100));
          end
          battery_max_discharge_power = ...
              min(simulation_parameters.converters(1).inverter_capacity - simulation_state.converters(1).inverter_power_output, ...
              simulation_state.batteries(1).max_discharge_power + simulation_state.batteries(1).power_setpoint*(inv_efficiency/100));
          battery_max_charge_power = ...
              min(simulation_parameters.converters(1).rectifier_capacity - simulation_state.converters(1).rectifier_power_output, ...
              simulation_state.batteries(1).max_charge_power -  simulation_state.batteries(1).power_setpoint);
          generator_max_possible_output_from_load_and_battery = matlab_simulation_variables.net_load + battery_max_charge_power/(rect_efficiency/100);
      else
          simulation_state.batteries(1).power_setpoint = 0;
          battery_max_discharge_power = 0;
          battery_max_charge_power = 0;
          generator_max_possible_output_from_load_and_battery = matlab_simulation_variables.net_load;
      end
      excess_solar_step_one = excess_solar_step_one - min(battery_max_charge_power, excess_solar_step_one/(inv_efficiency/100))*(inv_efficiency/100);
      
  end
 
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
 if matlab_simulation_variables.net_load <= epi
    % no need to turn on generator
    parameters(option_1,generator_power_setpoint) = 0;
    % inverter output equal to step 1
    parameters(option_1,inverter_power_output) = simulation_state.converters(1).inverter_power_output;
    % inverter input in dc adjusted by inverter efficiency
    parameters(option_1,inverter_power_input) = simulation_state.converters(1).inverter_power_input;
    % battery net charge equal to step 1
    parameters(option_1,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint;
    % rectifier input set to step 1
    parameters(option_1,rectifier_power_input) = simulation_state.converters(1).rectifier_power_input;
    % rectifier output set to step 1
    parameters(option_1,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
    % primary load served 
    parameters(option_1,primary_load_served) = simulation_state.ac_bus.load_requested;
    % ac bus excess electricity
    parameters(option_1,ac_bus_excess_electricity) = excess_solar_step_one + excess_wind_step_one;
    % ac bus load served
    parameters(option_1,ac_bus_load_served) = parameters(option_1,primary_load_served);
    % ac bus operating capacity requested: refelect requested load reserve
    parameters(option_1,ac_bus_operating_capacity_requested) = ...
        parameters(option_1,primary_load_served) + ...
        (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_1,primary_load_served);
    % ac bus operating capacity served: maximum capacity in ac
    if simulation_parameters.has_converter == true
       if simulation_parameters.has_battery == true 
           parameters(option_1,ac_bus_operating_capacity_served) = ...
               simulation_state.batteries(1).max_discharge_power + actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint;
       else
           parameters(option_1,ac_bus_operating_capacity_served) = actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint;
       end
    else
        parameters(option_1,ac_bus_operating_capacity_served) = simulation_state.wind_turbines(1).power_setpoint;
    end
    % ac bus unmet load
    parameters(option_1,ac_bus_unmet_load) = ...
        simulation_state.ac_bus.load_requested - parameters(option_1,primary_load_served);
    % ac bus capacity shortage
    if parameters(option_1,ac_bus_operating_capacity_served) > parameters(option_1,ac_bus_operating_capacity_requested)
        parameters(option_1,ac_bus_operating_capacity_served) = parameters(option_1,ac_bus_operating_capacity_requested);
    end
    parameters(option_1,ac_bus_capacity_shortage) = parameters(option_1,ac_bus_operating_capacity_requested) - parameters(option_1,ac_bus_operating_capacity_served);
else % we have positive net load
    if simulation_parameters.has_generator == true
        if simulation_parameters.has_battery == true && simulation_parameters.has_converter == true
            % we have battery & converter & generator
            if battery_max_discharge_power >= matlab_simulation_variables.net_load % we have enough energy stored in battery
                % no need to turn on generator
                parameters(option_1,generator_power_setpoint) = 0;
                % inverter output add on step 2
                parameters(option_1,inverter_power_output) = simulation_state.converters(1).inverter_power_output + matlab_simulation_variables.net_load;
                % inverter input in dc adjusted by inverter efficiency
                parameters(option_1,inverter_power_input) = parameters(option_1,inverter_power_output)/(inv_efficiency/100);
                % battery net charge add on step 2
                parameters(option_1,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint - matlab_simulation_variables.net_load/(inv_efficiency/100);
                % rectifier input set to step 1
                parameters(option_1,rectifier_power_input) = simulation_state.converters(1).rectifier_power_input;
                % rectifier output set to step 1
                parameters(option_1,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
                % primary load served
                parameters(option_1,primary_load_served) = parameters(option_1,inverter_power_output) + simulation_state.wind_turbines(1).power_setpoint;
                % ac bus excess electricity
                parameters(option_1,ac_bus_excess_electricity) = excess_solar_step_one + excess_wind_step_one;
                % ac bus load served
                parameters(option_1,ac_bus_load_served) = parameters(option_1,primary_load_served);
                % ac bus operating capacity requested: refelect requested load reserve
                parameters(option_1,ac_bus_operating_capacity_requested) = ...
                    parameters(option_1,primary_load_served) + ...
                    (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_1,primary_load_served);
                % ac bus operating capacity served: maximum capacity in ac
                parameters(option_1,ac_bus_operating_capacity_served) = ...
                    simulation_state.batteries(1).max_discharge_power + actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint;
                % ac bus unmet load
                parameters(option_1,ac_bus_unmet_load) = ...
                    simulation_state.ac_bus.load_requested - parameters(option_1,primary_load_served);
                % ac bus capacity shortage
                if parameters(option_1,ac_bus_operating_capacity_served) > parameters(option_1,ac_bus_operating_capacity_requested)
                    parameters(option_1,ac_bus_operating_capacity_served) = parameters(option_1,ac_bus_operating_capacity_requested);
                end
                parameters(option_1,ac_bus_capacity_shortage) = parameters(option_1,ac_bus_operating_capacity_requested) - parameters(option_1,ac_bus_operating_capacity_served);
            else % we need to turn on generator
                % remaining load after battery discharge in ac
                remain_load_in_theory = matlab_simulation_variables.net_load - battery_max_discharge_power;
                if remain_load_in_theory <= epi
                    % generator output: minimum load
                    parameters(option_1,generator_power_setpoint) = 0;
                    % inverter output in ac
                    parameters(option_1,inverter_power_output) = ...
                        simulation_state.converters(1).inverter_power_output + ...
                        max(0, matlab_simulation_variables.net_load - parameters(option_1,generator_power_setpoint));
                    % inverter input in dc
                    parameters(option_1,inverter_power_input) = parameters(option_1,inverter_power_output)/(inv_efficiency/100);
                    % battery net charge
                    parameters(option_1,battery_power_setpoint) = simulation_state.batteries(1).max_discharge_power;
                    % rectifier output in dc
                    parameters(option_1,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
                    % rectifier input in ac
                    parameters(option_1,rectifier_power_input) = parameters(option_1,rectifier_power_output)/(rect_efficiency/100);
                    % primary load served
                    parameters(option_1,primary_load_served) = simulation_state.ac_bus.load_requested;
                    % ac bus excess electricity
                    parameters(option_1,ac_bus_excess_electricity) = excess_solar_step_one + excess_wind_step_one;
                    % ac bus load served
                    parameters(option_1,ac_bus_load_served) = parameters(option_1,primary_load_served);
                    % ac bus operating capacity requested: reflect requested load reserve
                    parameters(option_1,ac_bus_operating_capacity_requested) = ...
                        parameters(option_1,primary_load_served) + ...
                        (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_1,primary_load_served);
                    % ac bus operating capacity served: maximum capacity in ac
                    parameters(option_1,ac_bus_operating_capacity_served) = ...
                        simulation_state.batteries(1).max_discharge_power + ...
                        actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint +...
                        simulation_state.generators(1).power_available;
                    % ac bus unmet load
                    parameters(option_1,ac_bus_unmet_load) = simulation_state.ac_bus.load_requested - parameters(option_1,primary_load_served);
                    % ac bus capacity shortage
                    if parameters(option_1,ac_bus_operating_capacity_served) > parameters(option_1,ac_bus_operating_capacity_requested)
                        parameters(option_1,ac_bus_operating_capacity_served) = parameters(option_1,ac_bus_operating_capacity_requested);
                    end
                    parameters(option_1,ac_bus_capacity_shortage) = parameters(option_1,ac_bus_operating_capacity_requested) - parameters(option_1,ac_bus_operating_capacity_served);
                    
                elseif remain_load_in_theory <= min_load % we will have to turn on generator to its min load
                    % generator output: minimum load
                    parameters(option_1,generator_power_setpoint) = min_load;
                    % inverter output in ac
                    parameters(option_1,inverter_power_output) = ...
                        simulation_state.converters(1).inverter_power_output + ...
                        max(0, matlab_simulation_variables.net_load - parameters(option_1,generator_power_setpoint));
                    % inverter input in dc
                    parameters(option_1,inverter_power_input) = parameters(option_1,inverter_power_output)/(inv_efficiency/100);
                    % battery net charge
                    if matlab_simulation_variables.net_load >= parameters(option_1,generator_power_setpoint)
                        parameters(option_1,battery_power_setpoint) = ...
                            simulation_state.batteries(1).power_setpoint  ...
                            - (matlab_simulation_variables.net_load - parameters(option_1,generator_power_setpoint))/(inv_efficiency/100);
                    else
                        parameters(option_1,battery_power_setpoint) = ...
                            simulation_state.batteries(1).power_setpoint  ... 
                            + min(simulation_parameters.converters(1).rectifier_capacity - simulation_state.converters(1).rectifier_power_output,...   
                            min(battery_max_charge_power, (parameters(option_1,generator_power_setpoint) - matlab_simulation_variables.net_load)*(rect_efficiency/100)));
                    end
                    % rectifier output in dc
                    if matlab_simulation_variables.net_load >= parameters(option_1,generator_power_setpoint)
                        parameters(option_1,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
                    else
                        parameters(option_1,rectifier_power_output) = ...
                            simulation_state.converters(1).rectifier_power_output + ...
                            min(simulation_parameters.converters(1).rectifier_capacity - simulation_state.converters(1).rectifier_power_output,...   
                            min(battery_max_charge_power, (parameters(option_1,generator_power_setpoint) - matlab_simulation_variables.net_load)*(rect_efficiency/100)));
                    end
                    % rectifier input in ac
                    parameters(option_1,rectifier_power_input) = parameters(option_1,rectifier_power_output)/(rect_efficiency/100);
                    % primary load served
                    parameters(option_1,primary_load_served) = simulation_state.ac_bus.load_requested;
                    % ac bus excess electricity
                    if matlab_simulation_variables.net_load >= parameters(option_1,generator_power_setpoint)
                        parameters(option_1,ac_bus_excess_electricity) = excess_solar_step_one + excess_wind_step_one;
                    else
                        parameters(option_1,ac_bus_excess_electricity) = ...
                            excess_solar_step_one + excess_wind_step_one ...
                            + parameters(option_1,generator_power_setpoint) - matlab_simulation_variables.net_load - ...
                            min(simulation_parameters.converters(1).rectifier_capacity - simulation_state.converters(1).rectifier_power_output,...   
                            min(battery_max_charge_power, (parameters(option_1,generator_power_setpoint) - matlab_simulation_variables.net_load)*(rect_efficiency/100)))/(rect_efficiency/100);
                    end
                    % ac bus load served
                    parameters(option_1,ac_bus_load_served) = parameters(option_1,primary_load_served);
                    % ac bus operating capacity requested: reflect requested load reserve
                    parameters(option_1,ac_bus_operating_capacity_requested) = ...
                        parameters(option_1,primary_load_served) + ...
                        (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_1,primary_load_served);
                    % ac bus operating capacity served: maximum capacity in ac
                    parameters(option_1,ac_bus_operating_capacity_served) = ...
                        simulation_state.batteries(1).max_discharge_power + ...
                        actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint +...
                        simulation_state.generators(1).power_available;
                    % ac bus unmet load
                    parameters(option_1,ac_bus_unmet_load) = simulation_state.ac_bus.load_requested - parameters(option_1,primary_load_served);
                    % ac bus capacity shortage
                    if parameters(option_1,ac_bus_operating_capacity_served) > parameters(option_1,ac_bus_operating_capacity_requested)
                        parameters(option_1,ac_bus_operating_capacity_served) = parameters(option_1,ac_bus_operating_capacity_requested);
                    end
                    parameters(option_1,ac_bus_capacity_shortage) = parameters(option_1,ac_bus_operating_capacity_requested) - parameters(option_1,ac_bus_operating_capacity_served);
                else % we will ramp up the generator to the maximum of capacity/remaining load
                    % generator output: minimum of remaining load and generator capacity
                    parameters(option_1,generator_power_setpoint) = min(remain_load_in_theory, simulation_state.generators(1).power_available);
                    % inverter output add on step 2
                    parameters(option_1,inverter_power_output) = simulation_state.converters(1).inverter_power_output + battery_max_discharge_power;
                    % inverter input in dc adjusted by inverter efficiency
                    parameters(option_1,inverter_power_input) = parameters(option_1,inverter_power_output)/(inv_efficiency/100);
                    % battery net charge add on step 2
                    parameters(option_1,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint  - battery_max_discharge_power/(inv_efficiency/100); 
                    % rectifier input set to step 1
                    parameters(option_1,rectifier_power_input) = simulation_state.converters(1).rectifier_power_input;
                    % rectifier output set to step 1
                    parameters(option_1,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
                    % primary load served
                    parameters(option_1,primary_load_served) = ...
                        parameters(option_1,inverter_power_output) + ...
                        simulation_state.wind_turbines(1).power_setpoint +...
                        parameters(option_1,generator_power_setpoint);
                    % ac bus excess electricity
                    parameters(option_1,ac_bus_excess_electricity) = excess_solar_step_one + excess_wind_step_one;
                    % ac bus load served
                    parameters(option_1,ac_bus_load_served) = parameters(option_1,primary_load_served);
                    % ac bus operating capacity requested: reflect requested load reserve
                    parameters(option_1,ac_bus_operating_capacity_requested) = ...
                        parameters(option_1,primary_load_served) + ...
                        (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_1,primary_load_served);
                    % ac bus operating capacity served: maximum capacity in ac
                    parameters(option_1,ac_bus_operating_capacity_served)= ...
                        simulation_state.batteries(1).max_discharge_power + ...
                        actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint +...
                        simulation_state.generators(1).power_available;
                    % ac bus unmet load
                    parameters(option_1,ac_bus_unmet_load) = ...
                        simulation_state.ac_bus.load_requested - parameters(option_1,primary_load_served);
                    % ac bus capacity shortage
                    if parameters(option_1,ac_bus_operating_capacity_served) > parameters(option_1,ac_bus_operating_capacity_requested)
                        parameters(option_1,ac_bus_operating_capacity_served) = parameters(option_1,ac_bus_operating_capacity_requested);
                    end
                    parameters(option_1,ac_bus_capacity_shortage) = parameters(option_1,ac_bus_operating_capacity_requested) - parameters(option_1,ac_bus_operating_capacity_served);
                end
            end
        else % we only have generator
             if matlab_simulation_variables.net_load <= epi
                % generator output: min load
                 parameters(option_1,generator_power_setpoint) = 0;
                 % inverter output equal to step 1
                 parameters(option_1,inverter_power_output) = simulation_state.converters(1).inverter_power_output;
                 % inverter input in dc adjusted by inverter efficiency
                 parameters(option_1,inverter_power_input) = parameters(option_1,inverter_power_output)/(inv_efficiency/100);
                 % battery net charge equal to step 1
                 parameters(option_1,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint; 
                 % rectifier input set to step 1
                 parameters(option_1,rectifier_power_input) = simulation_state.converters(1).rectifier_power_input;
                 % rectifier output set to step 1
                 parameters(option_1,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
                 % primary load served
                 parameters(option_1,primary_load_served) = simulation_state.ac_bus.load_requested;
                 % ac bus excess electricity
                 parameters(option_1,ac_bus_excess_electricity) = ...
                     excess_solar_step_one + excess_wind_step_one + ...
                     (parameters(option_1,generator_power_setpoint) - matlab_simulation_variables.net_load);
                 % ac bus load served
                 parameters(option_1,ac_bus_load_served) = parameters(option_1,primary_load_served);
                 % ac bus operating capacity requested: reflect requested load reserve
                 parameters(option_1,ac_bus_operating_capacity_requested) = ...
                     parameters(option_1,primary_load_served) + ...
                     (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_1,primary_load_served);
                 % ac bus operating capacity served: maximum capacity in ac
                 parameters(option_1,ac_bus_operating_capacity_served) = ...
                     simulation_state.wind_turbines(1).power_setpoint + simulation_state.generators(1).power_available;
                 % ac bus unmet load
                 parameters(option_1,ac_bus_unmet_load) = ...
                     simulation_state.ac_bus.load_requested - parameters(option_1,primary_load_served);
                 % ac bus capacity shortage
                 if parameters(option_1,ac_bus_operating_capacity_served) > parameters(option_1,ac_bus_operating_capacity_requested)
                     parameters(option_1,ac_bus_operating_capacity_served) = parameters(option_1,ac_bus_operating_capacity_requested);
                 end
                 parameters(option_1,ac_bus_capacity_shortage) = parameters(option_1,ac_bus_operating_capacity_requested) - parameters(option_1,ac_bus_operating_capacity_served); 
             elseif matlab_simulation_variables.net_load <= min_load
                 % generator output: min load
                 parameters(option_1,generator_power_setpoint) = min_load;
                 % inverter output equal to step 1
                 parameters(option_1,inverter_power_output) = simulation_state.converters(1).inverter_power_output;
                 % inverter input in dc adjusted by inverter efficiency
                 parameters(option_1,inverter_power_input) = parameters(option_1,inverter_power_output)/(inv_efficiency/100);
                 % battery net charge equal to step 1
                 parameters(option_1,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint; 
                 % rectifier input set to step 1
                 parameters(option_1,rectifier_power_input) = simulation_state.converters(1).rectifier_power_input;
                 % rectifier output set to step 1
                 parameters(option_1,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
                 % primary load served
                 parameters(option_1,primary_load_served) = simulation_state.ac_bus.load_requested;
                 % ac bus excess electricity
                 parameters(option_1,ac_bus_excess_electricity) = ...
                     excess_solar_step_one + excess_wind_step_one + ...
                     (parameters(option_1,generator_power_setpoint) - matlab_simulation_variables.net_load);
                 % ac bus load served
                 parameters(option_1,ac_bus_load_served) = parameters(option_1,primary_load_served);
                 % ac bus operating capacity requested: reflect requested load reserve
                 parameters(option_1,ac_bus_operating_capacity_requested) = ...
                     parameters(option_1,primary_load_served) + ...
                     (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_1,primary_load_served);
                 % ac bus operating capacity served: maximum capacity in ac
                 parameters(option_1,ac_bus_operating_capacity_served) = ...
                     simulation_state.wind_turbines(1).power_setpoint + simulation_state.generators(1).power_available;
                 % ac bus unmet load
                 parameters(option_1,ac_bus_unmet_load) = ...
                     simulation_state.ac_bus.load_requested - parameters(option_1,primary_load_served);
                 % ac bus capacity shortage
                 if parameters(option_1,ac_bus_operating_capacity_served) > parameters(option_1,ac_bus_operating_capacity_requested)
                     parameters(option_1,ac_bus_operating_capacity_served) = parameters(option_1,ac_bus_operating_capacity_requested);
                 end
                 parameters(option_1,ac_bus_capacity_shortage) = parameters(option_1,ac_bus_operating_capacity_requested) - parameters(option_1,ac_bus_operating_capacity_served);
             else
                 % generator output: minimum of remaining load and generator capacity
                 parameters(option_1,generator_power_setpoint) = min(matlab_simulation_variables.net_load, simulation_state.generators(1).power_available);
                 % inverter output equal to step 1
                 parameters(option_1,inverter_power_output) = simulation_state.converters(1).inverter_power_output;
                 % inverter input in dc adjusted by inverter efficiency
                 parameters(option_1,inverter_power_input) = parameters(option_1,inverter_power_output)/(inv_efficiency/100);
                 % battery net charge equal to step 1
                 parameters(option_1,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint; 
                 % rectifier input set to step 1
                 parameters(option_1,rectifier_power_input) = simulation_state.converters(1).rectifier_power_input;
                 % rectifier output set to step 1
                 parameters(option_1,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
                 % primary load served
                 parameters(option_1,primary_load_served) = ...
                     parameters(option_1,inverter_power_output) + ...
                     simulation_state.wind_turbines(1).power_setpoint +...
                     parameters(option_1,generator_power_setpoint);
                 % ac bus excess electricity
                 parameters(option_1,ac_bus_excess_electricity) = excess_solar_step_one + excess_wind_step_one;
                 % ac bus load served
                 parameters(option_1,ac_bus_load_served) = parameters(option_1,primary_load_served);
                 % ac bus operating capacity requested: reflect requested load reserve
                 parameters(option_1,ac_bus_operating_capacity_requested) = ...
                     parameters(option_1,primary_load_served) + ...
                     (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_1,primary_load_served);
                 % ac bus operating capacity served: maximum capacity in ac
                 parameters(option_1,ac_bus_operating_capacity_served) = ...
                     simulation_state.wind_turbines(1).power_setpoint + simulation_state.generators(1).power_available;
                 % ac bus unmet load
                 parameters(option_1,ac_bus_unmet_load) = ...
                     simulation_state.ac_bus.load_requested - parameters(option_1,primary_load_served);
                 % ac bus capacity shortage
                 if parameters(option_1,ac_bus_operating_capacity_served) > parameters(option_1,ac_bus_operating_capacity_requested)
                     parameters(option_1,ac_bus_operating_capacity_served) = parameters(option_1,ac_bus_operating_capacity_requested);
                 end
                 parameters(option_1,ac_bus_capacity_shortage) = parameters(option_1,ac_bus_operating_capacity_requested) - parameters(option_1,ac_bus_operating_capacity_served);
             end
        end
    else % if we do not have a generator
        parameters(option_1,generator_power_setpoint) = 0;
        % inverter output add on step 2
        if simulation_parameters.has_battery == true && simulation_parameters.has_converter == true
            parameters(option_1,inverter_power_output) = simulation_state.converters(1).inverter_power_output + ...
                min(simulation_parameters.converters(1).inverter_capacity - parameters(option_1,inverter_power_output), ...
                min(battery_max_discharge_power, matlab_simulation_variables.net_load));
        else
            parameters(option_1,inverter_power_output) = simulation_state.converters(1).inverter_power_output;
        end
        % inverter input in dc adjusted by inverter efficiency
        parameters(option_1,inverter_power_input) = parameters(option_1,inverter_power_output)/(inv_efficiency/100);
        % battery net charge add on step 2
        if simulation_parameters.has_battery == true && simulation_parameters.has_converter == true
            parameters(option_1,battery_power_setpoint) = ...
                simulation_state.batteries(1).power_setpoint  ...
                - min(simulation_parameters.converters(1).inverter_capacity - parameters(option_1,inverter_power_output), ...
                min(battery_max_discharge_power, matlab_simulation_variables.net_load))/(inv_efficiency/100);
        else
            parameters(option_1,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint;
        end
        % rectifier input set to step 1
        parameters(option_1,rectifier_power_input) = simulation_state.converters(1).rectifier_power_input;
        % rectifier output set to step 1
        parameters(option_1,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
        % primary load served 
        parameters(option_1,primary_load_served) = parameters(option_1,inverter_power_output) + simulation_state.wind_turbines(1).power_setpoint;
        % ac bus excess electricity
        parameters(option_1,ac_bus_excess_electricity) = excess_solar_step_one + excess_wind_step_one;
        % ac bus load served
        parameters(option_1,ac_bus_load_served) = parameters(option_1,primary_load_served);
        % ac bus operating capacity requested: refelect requested load reserve
        parameters(option_1,ac_bus_operating_capacity_requested) = ...
            parameters(option_1,primary_load_served) + ...
            (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_1,primary_load_served);
        % ac bus operating capacity served: maximum capacity in ac
        if simulation_parameters.has_battery == true && simulation_parameters.has_converter == true
            parameters(option_1,ac_bus_operating_capacity_served) = ...
                actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint + battery_max_discharge_power;
        else
            parameters(option_1,ac_bus_operating_capacity_served) = simulation_state.wind_turbines(1).power_setpoint;
        end
        % ac bus unmet load
        parameters(option_1,ac_bus_unmet_load) = simulation_state.ac_bus.load_requested - parameters(option_1,primary_load_served);
        % ac bus capacity shortage
        if parameters(option_1,ac_bus_operating_capacity_served) > parameters(option_1,ac_bus_operating_capacity_requested)
            parameters(option_1,ac_bus_operating_capacity_served) = parameters(option_1,ac_bus_operating_capacity_requested);
        end
        parameters(option_1,ac_bus_capacity_shortage) = parameters(option_1,ac_bus_operating_capacity_requested) - parameters(option_1,ac_bus_operating_capacity_served);
    end
end
   
   
      
 %%         
% option 2
if matlab_simulation_variables.net_load <= epi
    % no need to turn on generator
    parameters(option_2,generator_power_setpoint) = 0;
    % inverter output equal to step 1
    parameters(option_2,inverter_power_output) = simulation_state.converters(1).inverter_power_output;
    % inverter input in dc adjusted by inverter efficiency
    parameters(option_2,inverter_power_input) = parameters(option_2,inverter_power_output)/(inv_efficiency/100);
    % battery net charge equal to step 1
    parameters(option_2,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint;
    % rectifier input set to step 1
    parameters(option_2,rectifier_power_input) = simulation_state.converters(1).rectifier_power_input;
    % rectifier output set to step 1
    parameters(option_2,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
    % primary load served
    parameters(option_2,primary_load_served) = simulation_state.ac_bus.load_requested;
    % ac bus excess electricity
    parameters(option_2,ac_bus_excess_electricity) = excess_solar_step_one + excess_wind_step_one;
    % ac bus load served
    parameters(option_2,ac_bus_load_served) = parameters(option_2,primary_load_served);
    % ac bus operating capacity requested: refelect requested load reserve
    parameters(option_2,ac_bus_operating_capacity_requested) = ...
        parameters(option_2,primary_load_served) + ...
        (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_2,primary_load_served);
    % ac bus operating capacity served: maximum capacity in ac
    if simulation_parameters.has_converter == true
       if simulation_parameters.has_battery == true 
        parameters(option_2,ac_bus_operating_capacity_served) = ...
            simulation_state.batteries(1).max_discharge_power + actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint;
       else
           parameters(option_2,ac_bus_operating_capacity_served) = actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint;
       end
    else
        parameters(option_2,ac_bus_operating_capacity_served) = actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint;
    end
    % ac bus unmet load
    parameters(option_2,ac_bus_unmet_load) = ...
        simulation_state.ac_bus.load_requested - parameters(option_2,primary_load_served);
    % ac bus capacity shortage
    if parameters(option_2,ac_bus_operating_capacity_served) > parameters(option_2,ac_bus_operating_capacity_requested)
        parameters(option_2,ac_bus_operating_capacity_served) = parameters(option_2,ac_bus_operating_capacity_requested);
    end
    parameters(option_2,ac_bus_capacity_shortage) = parameters(option_2,ac_bus_operating_capacity_requested) - parameters(option_2,ac_bus_operating_capacity_served);
else % we have positive net load
    if simulation_parameters.has_generator == true
        if simulation_parameters.has_battery == true && simulation_parameters.has_converter == true
            % we have battery & converter & generator
            if matlab_simulation_variables.net_load <= min_load
                % generator output: minimum load
                parameters(option_2,generator_power_setpoint) = min_load;  
                % use the remaining to charge battery
                excess_generator_output = parameters(option_2,generator_power_setpoint) - matlab_simulation_variables.net_load;
                % rectifier output in DC, battery net charge, excess
                % electricity
                if battery_max_charge_power <= epi
                    % rectifier output in DC
                    parameters(option_2,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
                    % battery net charge
                    parameters(option_2,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint;
                    % ac bus excess electricity
                    parameters(option_2,ac_bus_excess_electricity) = excess_solar_step_one + excess_wind_step_one + excess_generator_output;
                else
                    % rectifier output in DC
                    parameters(option_2,rectifier_power_output) = ...
                        simulation_state.converters(1).rectifier_power_output + ...
                        min(simulation_parameters.converters(1).rectifier_capacity - simulation_state.converters(1).rectifier_power_output, ...
                        min(battery_max_charge_power, excess_generator_output*(rect_efficiency/100)));
                    % battery net charge
                    parameters(option_2,battery_power_setpoint) = ...
                        simulation_state.batteries(1).power_setpoint  + ...
                        min(simulation_parameters.converters(1).rectifier_capacity - simulation_state.converters(1).rectifier_power_output, ...
                        min(battery_max_charge_power, excess_generator_output*(rect_efficiency/100)));
                    % ac bus excess electricity
                    parameters(option_2,ac_bus_excess_electricity) = ...
                        excess_solar_step_one + excess_wind_step_one + ...
                        excess_generator_output - ...
                        (min(simulation_parameters.converters(1).rectifier_capacity - simulation_state.converters(1).rectifier_power_output, ...
                        min(battery_max_charge_power, excess_generator_output*(rect_efficiency/100))))/(rect_efficiency/100);
                end
                % rectifier input in AC
                parameters(option_2,rectifier_power_input) = parameters(option_2,rectifier_power_output)/(rect_efficiency/100);
                % inverter input set equal to 1st step
                parameters(option_2,inverter_power_input) = simulation_state.converters(1).inverter_power_input;
                % inverter output set equal to 1st step
                parameters(option_2,inverter_power_output) = simulation_state.converters(1).inverter_power_output;
                % primary load served
                parameters(option_2,primary_load_served) = simulation_state.ac_bus.load_requested;
                % ac bus load served
                parameters(option_2,ac_bus_load_served) = parameters(option_2,primary_load_served);
                % ac bus operating capacity requested
                parameters(option_2,ac_bus_operating_capacity_requested) = ...
                    parameters(option_2,primary_load_served) + ...
                    (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_2,primary_load_served);
                % ac bus operating capacity served
                parameters(option_2,ac_bus_operating_capacity_served) = ...
                    simulation_state.batteries(1).max_discharge_power + ...
                    actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint +...
                    simulation_state.generators(1).power_available;
                % as bus unmet load
                parameters(option_2,ac_bus_unmet_load) = simulation_state.ac_bus.load_requested - parameters(option_2,primary_load_served);
                % ac bus capacity shortage
                if parameters(option_2,ac_bus_operating_capacity_served) > parameters(option_2,ac_bus_operating_capacity_requested)
                    parameters(option_2,ac_bus_operating_capacity_served) = parameters(option_2,ac_bus_operating_capacity_requested);
                end
                parameters(option_2,ac_bus_capacity_shortage) = parameters(option_2,ac_bus_operating_capacity_requested) - parameters(option_2,ac_bus_operating_capacity_served);
            else % we will ramp up the generator to the maximum level of capacity/remaining load
                % generator output
                parameters(option_2,generator_power_setpoint) = ...
                    min(matlab_simulation_variables.net_load, simulation_state.generators(1).power_available);   
                % do we have unmet load here
                unmet_load = max(0, matlab_simulation_variables.net_load - simulation_state.generators(1).power_available);
                % discharge the battery to meet this unmet load if possible
                % inverter output
                parameters(option_2,inverter_power_output) = min(unmet_load, battery_max_discharge_power) + simulation_state.converters(1).inverter_power_output;
                % inverter input
                parameters(option_2,inverter_power_input) = parameters(option_2,inverter_power_output)/(inv_efficiency/100);
                % rectifier output
                parameters(option_2,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
                % rectifier input
                parameters(option_2,rectifier_power_input) = simulation_state.converters(1).rectifier_power_input;
                % battery net charge
                parameters(option_2,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint - min(unmet_load, battery_max_discharge_power)/(inv_efficiency/100);
                % primary load served
                parameters(option_2,primary_load_served) = ...
                    parameters(option_2,generator_power_setpoint) + parameters(option_2,inverter_power_output) + simulation_state.wind_turbines(1).power_setpoint;
                % ac bus excess electricity
                parameters(option_2,ac_bus_excess_electricity) = excess_solar_step_one + excess_wind_step_one;
                % ac bus load served
                parameters(option_2,ac_bus_load_served) = parameters(option_2,primary_load_served);
                % ac bus operating capacity requested
                parameters(option_2,ac_bus_operating_capacity_requested) = ...
                    parameters(option_2,primary_load_served) + ...
                    (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_2,primary_load_served);
                % ac bus operating capacity served
                parameters(option_2,ac_bus_operating_capacity_served) = ...
                    simulation_state.batteries(1).max_discharge_power + ...
                    actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint +...
                    simulation_state.generators(1).power_available;
                % as bus unmet load
                parameters(option_2,ac_bus_unmet_load) = simulation_state.ac_bus.load_requested - parameters(option_2,primary_load_served);
                % ac bus capacity shortage
                if parameters(option_2,ac_bus_operating_capacity_served) > parameters(option_2,ac_bus_operating_capacity_requested)
                    parameters(option_2,ac_bus_operating_capacity_served) = parameters(option_2,ac_bus_operating_capacity_requested);
                end
                parameters(option_2,ac_bus_capacity_shortage) = parameters(option_2,ac_bus_operating_capacity_requested) - parameters(option_2,ac_bus_operating_capacity_served);
            end
        else % we only have generator
            % generator output
            if matlab_simulation_variables.net_load <= min_load
                parameters(option_2,generator_power_setpoint) = min_load;  
            else
                parameters(option_2,generator_power_setpoint) = ...
                    min(matlab_simulation_variables.net_load, simulation_state.generators(1).power_available);   
            end
            % rectifier output in DC
            parameters(option_2,rectifier_power_output) = 0;
            % rectifier input in AC
            parameters(option_2,rectifier_power_input) = parameters(option_2,rectifier_power_output)/(rect_efficiency/100);
            % battery net charge
            parameters(option_2,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint;
            % inverter input set equal to 1st step
            parameters(option_2,inverter_power_input) = simulation_state.converters(1).inverter_power_input;
            % inverter output set equal to 1st step
            parameters(option_2,inverter_power_output) = simulation_state.converters(1).inverter_power_output;
            % primary load served
            parameters(option_2,primary_load_served) = ...
                min(parameters(option_2,generator_power_setpoint), matlab_simulation_variables.net_load) + ...
                simulation_state.ac_bus.load_requested - matlab_simulation_variables.net_load;
            % ac bus excess electricity
            parameters(option_2,ac_bus_excess_electricity) = ...
                excess_solar_step_one + excess_wind_step_one ...
                + max(0, parameters(option_2,generator_power_setpoint) - matlab_simulation_variables.net_load);
            % ac bus load served
            parameters(option_2,ac_bus_load_served) = parameters(option_2,primary_load_served);
            % ac bus operating capacity requested
            parameters(option_2,ac_bus_operating_capacity_requested) = ...
                parameters(option_2,primary_load_served) + ...
                (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_2,primary_load_served);
            % ac bus operating capacity served
            parameters(option_2,ac_bus_operating_capacity_served) = ...
                simulation_state.generators(1).power_available + simulation_state.wind_turbines(1).power_setpoint;
            % as bus unmet load
            parameters(option_2,ac_bus_unmet_load) = simulation_state.ac_bus.load_requested - parameters(option_2,primary_load_served);
            % ac bus capacity shortage
            if parameters(option_2,ac_bus_operating_capacity_served) > parameters(option_2,ac_bus_operating_capacity_requested)
                parameters(option_2,ac_bus_operating_capacity_served) = parameters(option_2,ac_bus_operating_capacity_requested);
            end
            parameters(option_2,ac_bus_capacity_shortage) = parameters(option_2,ac_bus_operating_capacity_requested) - parameters(option_2,ac_bus_operating_capacity_served);
        end
    else % we do not have generator
        parameters(option_2,generator_power_setpoint) = 0;
        % inverter output add on step 2
        if simulation_parameters.has_battery == true && simulation_parameters.has_converter == true
            parameters(option_2,inverter_power_output) = simulation_state.converters(1).inverter_power_output + ...
                min(simulation_parameters.converters(1).inverter_capacity - parameters(option_2,inverter_power_output), ...
                min(battery_max_discharge_power, matlab_simulation_variables.net_load));
        else
            parameters(option_2,inverter_power_output) = simulation_state.converters(1).inverter_power_output;
        end
        % inverter input in dc adjusted by inverter efficiency
        parameters(option_2,inverter_power_input) = parameters(option_2,inverter_power_output)/(inv_efficiency/100);
        % battery net charge add on step 2
        if simulation_parameters.has_battery == true && simulation_parameters.has_converter == true
            parameters(option_2,battery_power_setpoint) = ...
                simulation_state.batteries(1).power_setpoint - ...
                min(simulation_parameters.converters(1).inverter_capacity - parameters(option_2,inverter_power_output), ...
                min(battery_max_discharge_power, matlab_simulation_variables.net_load))/(inv_efficiency/100);
        else
            parameters(option_2,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint;
        end
        % rectifier input set to step 1
        parameters(option_2,rectifier_power_input) = simulation_state.converters(1).rectifier_power_input;
        % rectifier output set to step 1
        parameters(option_2,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
        % primary load served equal to inverter output
        parameters(option_2,primary_load_served) = parameters(option_2,inverter_power_output) + simulation_state.wind_turbines(1).power_setpoint;
        % ac bus excess electricity
        parameters(option_2,ac_bus_excess_electricity) = excess_solar_step_one + excess_wind_step_one;
        % ac bus load served
        parameters(option_2,ac_bus_load_served) = parameters(option_2,primary_load_served);
        % ac bus operating capacity requested: refelect requested load reserve
        parameters(option_2,ac_bus_operating_capacity_requested) = ...
            parameters(option_2,primary_load_served) + ...
            (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_2,primary_load_served);
        % ac bus operating capacity served: maximum capacity in ac
        if simulation_parameters.has_battery == true && simulation_parameters.has_converter == true
            parameters(option_2,ac_bus_operating_capacity_served) = ...
                actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint + battery_max_discharge_power;
        else
            parameters(option_2,ac_bus_operating_capacity_served) = simulation_state.wind_turbines(1).power_setpoint;
        end
        % ac bus unmet load
        parameters(option_2,ac_bus_unmet_load) = simulation_state.ac_bus.load_requested - parameters(option_2,primary_load_served);
        % ac bus capacity shortage
        if parameters(option_2,ac_bus_operating_capacity_served) > parameters(option_2,ac_bus_operating_capacity_requested)
            parameters(option_2,ac_bus_operating_capacity_served) = parameters(option_2,ac_bus_operating_capacity_requested);
        end
        parameters(option_2,ac_bus_capacity_shortage) = parameters(option_2,ac_bus_operating_capacity_requested) - parameters(option_2,ac_bus_operating_capacity_served);
    end
end

          
%%          
% option 3
if matlab_simulation_variables.net_load <= epi
    % turn on the generator to charge the battery
    if simulation_parameters.has_generator == true
        if simulation_parameters.has_battery == true && simulation_parameters.has_converter == true
            if generator_max_possible_output_from_load_and_battery <= epi
                parameters(option_3,generator_power_setpoint) = 0;
                parameters(option_3,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
                parameters(option_3,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint;
            elseif generator_max_possible_output_from_load_and_battery <= min_load
                parameters(option_3,generator_power_setpoint) = min_load;
                parameters(option_3,rectifier_power_output) = ...
                    simulation_state.converters(1).rectifier_power_output + ...
                    min(simulation_parameters.converters(1).rectifier_capacity - parameters(option_3,rectifier_power_output), battery_max_charge_power);
                parameters(option_3,battery_power_setpoint) = ...
                    simulation_state.batteries(1).power_setpoint + ...
                    min(simulation_parameters.converters(1).rectifier_capacity - parameters(option_3,rectifier_power_output), battery_max_charge_power);
            else
                parameters(option_3,generator_power_setpoint) = min(generator_max_possible_output_from_load_and_battery, simulation_state.generators(1).power_available);
                parameters(option_3,rectifier_power_output) = ...
                    simulation_state.converters(1).rectifier_power_output + ...
                    min(simulation_parameters.converters(1).rectifier_capacity - parameters(option_3,rectifier_power_output), ...
                    parameters(option_3,generator_power_setpoint)*(rect_efficiency/100));
                parameters(option_3,battery_power_setpoint) = ...
                    simulation_state.batteries(1).power_setpoint + ...
                    min(simulation_parameters.converters(1).rectifier_capacity - parameters(option_3,rectifier_power_output), ...
                    parameters(option_3,generator_power_setpoint)*(rect_efficiency/100));
            end
        else
           parameters(option_3,generator_power_setpoint) = 0;
           parameters(option_3,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
           parameters(option_3,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint;
        end
    else
        parameters(option_3,generator_power_setpoint) = 0;
        parameters(option_3,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
        parameters(option_3,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint;
    end
    % inverter output equal to step 1
    parameters(option_3,inverter_power_output) = simulation_state.converters(1).inverter_power_output;
    % inverter input in dc adjusted by inverter efficiency
    parameters(option_3,inverter_power_input) = parameters(option_3,inverter_power_output)/(inv_efficiency/100);
    % rectifier input 
    parameters(option_3,rectifier_power_input) = simulation_state.converters(1).rectifier_power_output/(rect_efficiency/100);
    % primary load served equal to inverter output (pv output in step 1)
    parameters(option_3,primary_load_served) = simulation_state.ac_bus.load_requested;
    % ac bus excess electricity
    parameters(option_3,ac_bus_excess_electricity) = ...
        excess_solar_step_one + excess_wind_step_one + ...
        parameters(option_3,generator_power_setpoint) - parameters(option_3,rectifier_power_input);
    % ac bus load served
    parameters(option_3,ac_bus_load_served) = parameters(option_3,primary_load_served);
    % ac bus operating capacity requested: refelect requested load reserve
    parameters(option_3,ac_bus_operating_capacity_requested) = ...
        parameters(option_3,primary_load_served) + ...
        (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_3,primary_load_served);
    % ac bus operating capacity served: maximum capacity in ac
    if simulation_parameters.has_converter == true
       if simulation_parameters.has_battery == true 
        parameters(option_3,ac_bus_operating_capacity_served) = ...
            simulation_state.batteries(1).max_discharge_power + actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint + parameters(option_3,generator_power_setpoint);
       else
           parameters(option_3,ac_bus_operating_capacity_served) = actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint + parameters(option_3,generator_power_setpoint);
       end
    else
        parameters(option_3,ac_bus_operating_capacity_served) = simulation_state.wind_turbines(1).power_setpoint + parameters(option_3,generator_power_setpoint);
    end
    % ac bus unmet load
    parameters(option_3,ac_bus_unmet_load) = ...
        simulation_state.ac_bus.load_requested - parameters(option_3,primary_load_served);
    % ac bus capacity shortage
    if parameters(option_3,ac_bus_operating_capacity_served) > parameters(option_3,ac_bus_operating_capacity_requested)
        parameters(option_3,ac_bus_operating_capacity_served) = parameters(option_3,ac_bus_operating_capacity_requested);
    end
    parameters(option_3,ac_bus_capacity_shortage) = parameters(option_3,ac_bus_operating_capacity_requested) - parameters(option_3,ac_bus_operating_capacity_served);

else % we have positive net load
    if simulation_parameters.has_generator == true
        if simulation_parameters.has_battery == true && simulation_parameters.has_converter == true
            % we have battery & converter & generator
            if generator_max_possible_output_from_load_and_battery <= min_load % we will run generator at the minimun load
                % inverter input
                parameters(option_3,inverter_power_input) = simulation_state.converters(1).inverter_power_input;
                % inverter output
                parameters(option_3,inverter_power_output) = simulation_state.converters(1).inverter_power_output;
                % generator output: minimum load
                parameters(option_3,generator_power_setpoint) = min_load;
                % rectifier output
                if battery_max_charge_power <= epi
                    parameters(option_3,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
                    % ac bus excess electricity
                    parameters(option_3,ac_bus_excess_electricity) = ...
                        excess_solar_step_one + excess_wind_step_one + ...
                        parameters(option_3,generator_power_setpoint) - matlab_simulation_variables.net_load;
                    % battery net charge
                    parameters(option_3,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint;
                else
                    parameters(option_3,rectifier_power_output) = ...
                        simulation_state.converters(1).rectifier_power_output + ...
                        min(simulation_parameters.converters(1).rectifier_capacity - parameters(option_3,rectifier_power_output), ...
                        min(battery_max_charge_power, (parameters(option_3,generator_power_setpoint) - matlab_simulation_variables.net_load)*(rect_efficiency/100)));
                    % ac bus excess electricity
                    parameters(option_3,ac_bus_excess_electricity) = ...
                        excess_solar_step_one + excess_wind_step_one + ...
                        parameters(option_3,generator_power_setpoint) - matlab_simulation_variables.net_load - ...
                        min(simulation_parameters.converters(1).rectifier_capacity - parameters(option_3,rectifier_power_output), ...
                        min(battery_max_charge_power, (parameters(option_3,generator_power_setpoint) - matlab_simulation_variables.net_load)*(rect_efficiency/100)))/(rect_efficiency/100);
                    % battery net charge
                    parameters(option_3,battery_power_setpoint) = ...
                        simulation_state.batteries(1).power_setpoint + ...
                        min(simulation_parameters.converters(1).rectifier_capacity - parameters(option_3,rectifier_power_output), ...
                        min(battery_max_charge_power, (parameters(option_3,generator_power_setpoint) - matlab_simulation_variables.net_load)*(rect_efficiency/100)));                   
                end
                % rectifier input
                parameters(option_3,rectifier_power_input) = parameters(option_3,rectifier_power_output)/(rect_efficiency/100);
                % primary load served
                parameters(option_3,primary_load_served) = simulation_state.ac_bus.load_requested;
                % ac bus load served
                parameters(option_3,ac_bus_load_served) = parameters(option_3,primary_load_served);
                % ac bus operating capacity requested
                parameters(option_3,ac_bus_operating_capacity_requested) = ...
                    parameters(option_3,primary_load_served) + ...
                    (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_3,primary_load_served);
                % ac bus operating capacity served
                parameters(option_3,ac_bus_operating_capacity_served) = ...
                    simulation_state.batteries(1).max_discharge_power + ...
                    actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint +...
                    simulation_state.generators(1).power_available;
                % as bus unmet load
                parameters(option_3,ac_bus_unmet_load) = ...
                    simulation_state.ac_bus.load_requested - parameters(option_3,primary_load_served);
                % ac bus capacity shortage
                if parameters(option_3,ac_bus_operating_capacity_served) > parameters(option_3,ac_bus_operating_capacity_requested)
                    parameters(option_3,ac_bus_operating_capacity_served) = parameters(option_3,ac_bus_operating_capacity_requested);
                end
                parameters(option_3,ac_bus_capacity_shortage) = parameters(option_3,ac_bus_operating_capacity_requested) - parameters(option_3,ac_bus_operating_capacity_served);
            else % we will ramp up the generator to the maxmum level possible
                % generator output
                parameters(option_3,generator_power_setpoint) = ...
                    min(generator_max_possible_output_from_load_and_battery, simulation_state.generators(1).power_available);    
                % if we have unmet load, discharge battery to meet the remaining if possible
                remain_load = max(0,matlab_simulation_variables.net_load - parameters(option_3,generator_power_setpoint));
                if remain_load > 0 % we run generator at full capacity with battery assistance, this is equal to option 2
                    % inverter output
                    parameters(option_3,inverter_power_output) = ...
                        min(simulation_parameters.converters(1).inverter_capacity - simulation_state.converters(1).inverter_power_output,...
                        min(remain_load, battery_max_discharge_power)) ...
                        + simulation_state.converters(1).inverter_power_output;
                    % inverter input
                    parameters(option_3,inverter_power_input) = parameters(option_3,inverter_power_output)/(inv_efficiency/100);
                    % rectifier output
                    parameters(option_3,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
                    % rectifier input
                    parameters(option_3,rectifier_power_input) = simulation_state.converters(1).rectifier_power_input;
                    % battery net charge
                    parameters(option_3,battery_power_setpoint) = ...
                        simulation_state.batteries(1).power_setpoint ...
                        - min(simulation_parameters.converters(1).inverter_capacity - simulation_state.converters(1).inverter_power_output,...
                        min(remain_load, battery_max_discharge_power))/(inv_efficiency/100);
                    % primary load served
                    parameters(option_3,primary_load_served) = ...
                        parameters(option_3,generator_power_setpoint) + parameters(option_3,inverter_power_output) ...
                        + simulation_state.wind_turbines(1).power_setpoint;
                    % ac bus excess electricity
                    parameters(option_3,ac_bus_excess_electricity) = excess_solar_step_one + excess_wind_step_one;
                else % we do not have remaining load
                    % inverter input
                    parameters(option_3,inverter_power_input) = simulation_state.converters(1).inverter_power_input;
                    % inverter output
                    parameters(option_3,inverter_power_output) = simulation_state.converters(1).inverter_power_output;
                    % rectifier output
                    parameters(option_3,rectifier_power_output) = ...
                        simulation_state.converters(1).rectifier_power_output + ...
                        min((parameters(option_3,generator_power_setpoint) - matlab_simulation_variables.net_load)*(rect_efficiency/100), ...
                        simulation_parameters.converters(1).rectifier_capacity - parameters(option_3,rectifier_power_output));
                    % rectifier input
                    parameters(option_3,rectifier_power_input) = parameters(option_3,rectifier_power_output)/(rect_efficiency/100);
                    % battery net charge
                    parameters(option_3,battery_power_setpoint) = ...
                        simulation_state.batteries(1).power_setpoint + ...
                        min((parameters(option_3,generator_power_setpoint) - matlab_simulation_variables.net_load)*(rect_efficiency/100), ...
                        simulation_parameters.converters(1).rectifier_capacity - parameters(option_3,rectifier_power_output));
                    % primary load served
                    parameters(option_3,primary_load_served) = simulation_state.ac_bus.load_requested;
                    % ac bus excess electricity
                    parameters(option_3,ac_bus_excess_electricity) = ...
                        excess_solar_step_one + excess_wind_step_one + ...
                        parameters(option_3,generator_power_setpoint) - matlab_simulation_variables.net_load ...
                        - min((parameters(option_3,generator_power_setpoint) - matlab_simulation_variables.net_load)*(rect_efficiency/100), ...
                        simulation_parameters.converters(1).rectifier_capacity - parameters(option_3,rectifier_power_output))/(rect_efficiency/100); 
                end
                % ac bus load served
                parameters(option_3,ac_bus_load_served) = parameters(option_3,primary_load_served);
                % ac bus operating capacity requested
                parameters(option_3,ac_bus_operating_capacity_requested) = ...
                    parameters(option_3,primary_load_served) + ...
                    (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_3,primary_load_served);
                % ac bus operating capacity served
                parameters(option_3,ac_bus_operating_capacity_served) = ...
                    simulation_state.batteries(1).max_discharge_power + ...
                    actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint +...
                    simulation_state.generators(1).power_available;
                % as bus unmet load
                parameters(option_3,ac_bus_unmet_load) = ...
                    simulation_state.ac_bus.load_requested - parameters(option_3,primary_load_served);
                % ac bus capacity shortage
                if parameters(option_3,ac_bus_operating_capacity_served) > parameters(option_3,ac_bus_operating_capacity_requested)
                    parameters(option_3,ac_bus_operating_capacity_served) = parameters(option_3,ac_bus_operating_capacity_requested);
                end
                parameters(option_3,ac_bus_capacity_shortage) = parameters(option_3,ac_bus_operating_capacity_requested) - parameters(option_3,ac_bus_operating_capacity_served);
            end

        else % we only have generator
            % generator output
            if matlab_simulation_variables.net_load <= min_load
                parameters(option_3,generator_power_setpoint) = min_load;  
            else
                parameters(option_3,generator_power_setpoint) = ...
                    min(matlab_simulation_variables.net_load, simulation_state.generators(1).power_available);   
            end
            % rectifier output in DC
            parameters(option_3,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
            % rectifier input in AC
            parameters(option_3,rectifier_power_input) = parameters(option_3,rectifier_power_output)/(rect_efficiency/100);
            % battery net charge
            parameters(option_3,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint;
            % inverter input set equal to 1st step
            parameters(option_3,inverter_power_input) = simulation_state.converters(1).inverter_power_input;
            % inverter output set equal to 1st step
            parameters(option_3,inverter_power_output) = simulation_state.converters(1).inverter_power_output;
            % primary load served
            parameters(option_3,primary_load_served) = ...
                min(parameters(option_3,generator_power_setpoint), matlab_simulation_variables.net_load) + ...
                simulation_state.ac_bus.load_requested - matlab_simulation_variables.net_load;
            % ac bus excess electricity
            parameters(option_3,ac_bus_excess_electricity) = ...
                excess_solar_step_one + excess_wind_step_one ...
                + max(0, parameters(option_3,generator_power_setpoint) - matlab_simulation_variables.net_load);
            % ac bus load served
            parameters(option_3,ac_bus_load_served) = parameters(option_3,primary_load_served);
            % ac bus operating capacity requested
            parameters(option_3,ac_bus_operating_capacity_requested) = ...
                parameters(option_3,primary_load_served) + ...
                (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_3,primary_load_served);
            % ac bus operating capacity served
            parameters(option_3,ac_bus_operating_capacity_served) = simulation_state.generators(1).power_available + simulation_state.wind_turbines(1).power_setpoint;
            % as bus unmet load
            parameters(option_3,ac_bus_unmet_load) = simulation_state.ac_bus.load_requested - parameters(option_3,primary_load_served);
            % ac bus capacity shortage
            if parameters(option_3,ac_bus_operating_capacity_served) > parameters(option_3,ac_bus_operating_capacity_requested)
                parameters(option_3,ac_bus_operating_capacity_served) = parameters(option_3,ac_bus_operating_capacity_requested);
            end
            parameters(option_3,ac_bus_capacity_shortage) = parameters(option_3,ac_bus_operating_capacity_requested) - parameters(option_3,ac_bus_operating_capacity_served);
        end
    else % we do not have a generator
        parameters(option_3,generator_power_setpoint) = 0;
        % inverter output add on step 2
        if simulation_parameters.has_battery == true && simulation_parameters.has_converter == true
            parameters(option_3,inverter_power_output) = ...
                simulation_state.converters(1).inverter_power_output + ...
                min(simulation_parameters.converters(1).inverter_capacity - parameters(option_3,inverter_power_output), ...
                min(battery_max_discharge_power, matlab_simulation_variables.net_load));
        else
            parameters(option_3,inverter_power_output) = simulation_state.converters(1).inverter_power_output;
        end
        % inverter input in dc adjusted by inverter efficiency
        parameters(option_3,inverter_power_input) = parameters(option_3,inverter_power_output)/(inv_efficiency/100);
        % battery net charge add on step 2
        if simulation_parameters.has_battery == true && simulation_parameters.has_converter == true
            parameters(option_3,battery_power_setpoint) = ...
                simulation_state.batteries(1).power_setpoint ...
                - min(simulation_parameters.converters(1).inverter_capacity - parameters(option_3,inverter_power_output), ...
                min(battery_max_discharge_power, matlab_simulation_variables.net_load))/(inv_efficiency/100);
        else
            parameters(option_3,battery_power_setpoint)= simulation_state.batteries(1).power_setpoint ;
        end
        % rectifier input set to step 1
        parameters(option_3,rectifier_power_input) = simulation_state.converters(1).rectifier_power_input;
        % rectifier output set to step 1
        parameters(option_3,rectifier_power_output) = simulation_state.converters(1).rectifier_power_output;
        % primary load served equal to inverter output
        parameters(option_3,primary_load_served) = parameters(option_3,inverter_power_output) + simulation_state.wind_turbines(1).power_setpoint;
        % ac bus excess electricity
        parameters(option_3,ac_bus_excess_electricity) = excess_solar_step_one + excess_wind_step_one;
        % ac bus load served
        parameters(option_3,ac_bus_load_served) = parameters(option_3,primary_load_served);
        % ac bus operating capacity requested: refelect requested load reserve
        parameters(option_3,ac_bus_operating_capacity_requested) = ...
            parameters(option_3,primary_load_served) + ...
            (simulation_parameters.operating_reserve.timestep_requirement/100) * parameters(option_3,primary_load_served);
        % ac bus operating capacity served: maximum capacity in ac
        if simulation_parameters.has_battery == true
            parameters(option_3,ac_bus_operating_capacity_served) = ...
                actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint + battery_max_discharge_power;
        else
            parameters(option_3,ac_bus_operating_capacity_served) = actual_inverted_power + simulation_state.wind_turbines(1).power_setpoint;
        end
        % ac bus unmet load
        parameters(option_3,ac_bus_unmet_load) = simulation_state.ac_bus.load_requested - parameters(option_3,primary_load_served);
        % ac bus capacity shortage
        if parameters(option_3,ac_bus_operating_capacity_served) > parameters(option_3,ac_bus_operating_capacity_requested)
            parameters(option_3,ac_bus_operating_capacity_served) = parameters(option_3,ac_bus_operating_capacity_requested);
        end
        parameters(option_3,ac_bus_capacity_shortage) = parameters(option_3,ac_bus_operating_capacity_requested) - parameters(option_3,ac_bus_operating_capacity_served);
    end
end
 


 %%
 
 % costs
%parameters(:,marginal_cost) = ...
%    % if generator is turned on, calculate fuel cost
%    matlab_simulation_variables.generator_fuel_cost * parameters(:,generator_power_setpoint)/matlab_simulation_variables.net_load ...
%    % if generator is turned on, calculate O&M cost
%    + (parameters(:,generator_power_setpoint)>0) * matlab_simulation_variables.generator_OM / matlab_simulation_variables.net_load ...
    
%    % if battery is discharged, calculate the fuel cost of stored energy
%    + simulation_state.batteries(1).energy_cost * parameters(:,inverter_power_output)/matlab_simulation_variables.net_load ...
%    % if battery is discharged, calculate the battery wear cost of discharging
%    + simulation_parameters.batteries(1).wear_cost * parameters(:,inverter_power_output)/matlab_simulation_variables.net_load ...
%    % if battery is charged, calculate the battery wear cost of charging
%    + simulation_parameters.batteries(1).wear_cost * parameters(:,rectifier_power_input)/matlab_simulation_variables.net_load ...
%    % if battery is discharged, add on the value of stored energy
%    + matlab_simulation_variables.electricity_price * parameters(:,inverter_power_output)/matlab_simulation_variables.net_load ...
%    % if battery is charged, take out the value of stored energy
%    - matlab_simulation_variables.electricity_price * parameters(:,rectifier_power_input)/matlab_simulation_variables.net_load ...
    
%    % add on the value of unmet load if there is any
%    + matlab_simulation_variables.electricity_price * parameters(:,ac_bus_unmet_load)/matlab_simulation_variables.net_load;     
 
if simulation_parameters.has_battery == true
    parameters(:,marginal_cost) = ...
    (matlab_simulation_variables.generator_fuel_cost * parameters(:,generator_power_setpoint))/matlab_simulation_variables.net_load ...
    + (parameters(:,generator_power_setpoint)>0) * matlab_simulation_variables.generator_OM / matlab_simulation_variables.net_load ...
    + simulation_state.batteries(1).energy_cost * parameters(:,inverter_power_output)/matlab_simulation_variables.net_load ...
    + simulation_parameters.batteries(1).wear_cost * parameters(:,inverter_power_output)/matlab_simulation_variables.net_load ...
    + simulation_parameters.batteries(1).wear_cost * parameters(:,rectifier_power_input)/matlab_simulation_variables.net_load  ...
    + matlab_simulation_variables.electricity_price * parameters(:,inverter_power_output)/matlab_simulation_variables.net_load ...
    - matlab_simulation_variables.electricity_price * parameters(:,rectifier_power_input)/matlab_simulation_variables.net_load ...
    + matlab_simulation_variables.electricity_price * parameters(:,ac_bus_unmet_load)/matlab_simulation_variables.net_load;
else
    parameters(:,marginal_cost) = ...
    (matlab_simulation_variables.generator_fuel_cost * parameters(:,generator_power_setpoint))/matlab_simulation_variables.net_load ...
    + (parameters(:,generator_power_setpoint)>0) * matlab_simulation_variables.generator_OM / matlab_simulation_variables.net_load ...
    + matlab_simulation_variables.electricity_price * parameters(:,ac_bus_unmet_load)/matlab_simulation_variables.net_load;
end

    
costs = parameters(:,marginal_cost);
          
indx_min_cost = find(costs == min(costs));

% if there is a tie, always choose the one that charge the battery most
if length(indx_min_cost)>1
    indx_min_cost = max(indx_min_cost);
end

simulation_state.generators(1).power_setpoint          = parameters(indx_min_cost,generator_power_setpoint);
simulation_state.converters(1).inverter_power_input    = parameters(indx_min_cost,inverter_power_input);
simulation_state.converters(1).inverter_power_output   = parameters(indx_min_cost,inverter_power_output);
simulation_state.converters(1).rectifier_power_input   = parameters(indx_min_cost,rectifier_power_input);
simulation_state.converters(1).rectifier_power_output  = parameters(indx_min_cost,rectifier_power_output);
simulation_state.batteries(1).power_setpoint           = parameters(indx_min_cost,battery_power_setpoint);
simulation_state.primary_loads(1).load_served          = parameters(indx_min_cost,primary_load_served);
simulation_state.ac_bus.excess_electricity             = parameters(indx_min_cost,ac_bus_excess_electricity);
simulation_state.ac_bus.load_served                    = parameters(indx_min_cost,ac_bus_load_served);
%simulation_state.ac_bus.operating_capacity_requested   = parameters(indx_min_cost,ac_bus_operating_capacity_requested);
simulation_state.ac_bus.operating_capacity_served      = parameters(indx_min_cost,ac_bus_operating_capacity_served);
simulation_state.ac_bus.unmet_load                     = parameters(indx_min_cost,ac_bus_unmet_load);
simulation_state.ac_bus.capacity_shortage              = simulation_state.ac_bus.operating_capacity_requested - simulation_state.ac_bus.operating_capacity_served;
          
end
