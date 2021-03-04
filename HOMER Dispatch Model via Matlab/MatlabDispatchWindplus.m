% setting: 1 generator(ac), 1 pv(dc), 1 battery(dc), 1 electric load(ac)， 1
% wind turbine
% see definition of variables here: https://www.homerenergy.com/products/pro/docs/latest/_listing_of_simulationstate.html

eps = 0.00001;

% initiate an zero array for storing the output parameters, 3 rows for three choices and 14 columns for 14 variables 
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


% goal: use renewables to shave peak demand and save fuel
% battery: bounded by remaining space, converter/inverter capacity
% generator: min load, max load, converter capacity

% initialize all state variables related to DC load to 0
% 
% inputs
% ------
% simulation_state : object holding current state of simulation
% outputs
% ------
% simulation_state : object holding current state of simulation
%
function simulation_state = ignore_dc(simulation_state)
    simulation_state.dc_bus.capacity_shortage = 0;
    simulation_state.dc_bus.excess_electricity = 0;
    simulation_state.dc_bus.load_served = 0;
    simulation_state.dc_bus.operating_capacity_served = 0;
    simulation_state.dc_bus.unmet_load = 0;

% increment the power flowing through the rectifier on both the input and output
%
% assumes that dc_power is less than remaining capacity in rectifier
%
% inputs
% ------
% simulation_state : object holding current state of the simulation
% dc_power : the increment of DC power being delivered by the rectifier
% rect_efficiency : the AC->DC efficiency of the rectifier
%
% outputs
% ------
% simulation_state : object holding current state of the simulation
function simulation_state = increment_rectifier_load(simulation_state, dc_power, rect_efficiency)
    
    simulation_state.converters(1).rectifier_power_output = simulation_state.converters(1).rectifier_power_output + dc_power;
    simulation_state.converters(1).rectifier_power_input = simulation_state.converters(1).rectifier_powwer_input / (rect_efficiency/100);

end

% increment the power flowing through the inverter on both the input and output
%
% assumes that ac_power is less than remaining capacity in inverter
%
% simulation_state : object holding current state of the simulation
% ac_power: the increment of AC power being delivered by the inverter
% inv_efficiency : the DC->AC efficiency of the rectifier
%
function simulation_state = increment_inverter_load(simulation_state, ac_power, inv_efficiency)

    simulation_state.converters(1).inverter_power_output = simulation_state.converters(1).inverter_power_output + ac_power;
    simulation_state.converters(1).inverter_power_input = simulation_state.converters(1).inverter_power_output / ...
                                                          (inv_efficiency/100); 
end

% query the remaining DC charge available in the battery
% without changing the charge state
% 
% inputs
% ------
% simulation_state : object holding current state of simulation
% simulation_parameters : object holding current parameters of simulation
% dc_power : DC power available to charge batteries
%
% outputs
% -------
% charge_power : DC power used to charge batteries
%
function charge_power = get_battery_dc_charge_power(simulation_state, simulation_parameters, dc_power)

    charge_power = 0;

    if simulation_parameters.has_battery == true
        max_avail_battery_charge_power = simulation_state.batteries(1).max_charge_power - simulation_state.batteries(1).power_setpoint;

        charge_power = min(max_avail_battery_charge_power, dc_power)
    end  
end

% query the remaining AC charge available in the battery
% without changing the charge state
% 
% inputs
% ------
% simulation_state : object holding current state of simulation
% simulation_parameters : object holding current parameters of simulation
% ac_power : DC power available to charge batteries
% rect_efficiency : the AC->DC efficiency of the rectifier
%
% outputs
% -------
% ac_charging_power : AC power used to charge batteries
%
function ac_charging_power = get_battery_ac_charge_power(simulation_state, simulation_parameters, ac_power, rect_efficiency)

    dc_power = ac_power * rect_efficiency/100;

    max_avail_rectifier_output = simulation_parameters.converters(1).rectifier_capacity - simulation_state.converters(1).rectifier_power_output;

    dc_power_for_charging = min(dc_power, max_avail_rectifier_output);

    dc_charging_power = get_battery_dc_charge_power(simulation_state, simulation_parameters, dc_power_for_charging);

    ac_charging_power = dc_charging_power / (rect_efficiency/100);

end

% charge the batteries with DC power
% 
% inputs
% ------
% simulation_state : object holding current state of simulation
% dc_power : DC power available to charge batteries
%
% outputs
% -------
% simulation_state : object holding current state of simulation
% charge_power : DC power used to charge batteries
%
function [charge_power, simulation_state] = charge_batteries_dc(simulation_state, simulation_parameters, dc_power)

    charge_power = get_battery_dc_charge_power(simulation_state, simulation_parameters, dc_power);

    simulation_state.batteries(1).power_setpoint = simulation_state.batteries(1).power_setpoint + charge_power;
    
end

% charge the batteries with AC power
% 
% inputs
% ------
% simulation_state : object holding current state of simulation
% ac_power : DC power available to charge batteries
% rect_efficiency : the AC->DC efficiency of the rectifier
%
% outputs
% -------
% simulation_state : object holding current state of simulation
% ac_charging_power : AC power used to charge batteries
%
function [ac_charging_power, simulation_state] = charge_batteries_ac(simulation_state, simulation_parameters, ac_power, rect_efficiency)

    dc_power = ac_power * rect_efficiency/100;

    max_avail_rectifier_output = simulation_parameters.converters(1).rectifier_capacity - simulation_state.converters(1).rectifier_power_output;

    dc_power_for_charging = min(dc_power, max_avail_rectifier_output);

    dc_charging_power, simulation_state = charge_batteries_dc(simulation_state, simulation_parameters, dc_power_for_charging);

    simulation_state = increment_rectifier_load(simulation_state, dc_charging_power, rect_efficiency);
    ac_charging_power = dc_charging_power / (rect_efficiency/100);

end

% Dispatch generator to deliver AC power
%
% Query's the available power without changing the generator's state
% 
% inputs
% ------
% simulation_state : object holding current state of simulation
% simulation_parameters : object holding current parameters of simulation
% power : AC power requested from generator
%
% outputs
% -------
% avail_generator_power : AC generator power available for dispatch
%
function avail_generator_power = dispatch_generator(simulation_state, simulation_parameters, power)

    avail_generator_power = 0;

    if simulation_parameters.has_generator == true
        min_load = simulation_parameters.generators(1).minimum_load;
        max_load = simulation_state.generators(1).power_available;
        if power < eps
            avail_generator_power = 0;
        elseif power < min_load
            avail_generator_power = min_load;
        elseif power < max_load
            avail_generator_power = power;
        else
            avail_generator_power = max_load;
        end  
    end

end

% Dispatch batteries to deliver AC power
%
% Queries the system's ability to provide AC power from batteries 
% without changing the charge state.
% 
% inputs
% ------
% simulation_state : object holding current state of simulation
% simulation_parameters : object holding current parameters of simulation
% load : AC power requested from batteries
%
% outputs
% -------
% avail_battery_power : AC battery power available for dispatch
%
function avail_battery_power = dispatch_batteries(simulation_state, simulation_parameters, load, inv_efficiency)

    avail_battery_power = 0;

    if simulation_parameters.has_battery == true
        avail_inverter_ac_capacity = simulation_parameters.converters(1).inverter_capacity - simulation_state.converters(1).inverter_power_output;
        avail_battery_dc_capacity = simulation_state.batteries(1).max_discharge_power + simulation_state.batteries(1).power_setpoint;
        avail_battery_ac_capacity = avail_battery_dc_capacity / (inv_efficiency/100);
        battery_max_discharge_power = min(avail_inverter_ac_capacity, avail_battery_ac_capacity);
        
        if battery_max_discharge_power >= load;
            avail_battery_power = load;
        else
            avail_battery_power = battery_max_discharge_power;
        end
    end
end

% Dispatch wind to deliver AC power
% 
% inputs
% ------
% simulation_state : object holding current state of simulation
% simulation_parameters : object holding current parameters of simulation
% load : AC power requested from wind
%
% outputs
% -------
% avail_wind_power : AC wind power available for dispatch
% simulation_state : object holding current state of simulation
%
function [avail_wind_power, simulation_state] = dispatch_wind(simulation_state, simulation_parameters, load)

  % dispatch wind power to AC network
  simulation_state.wind_turbines(1).power_setpoint = 0;
  if simulation_parameters.has_wind_turbine == true
      simulation_state.wind_turbines(1).power_setpoint = simulation_state.wind_turbines(1).power_available;
  end
  avail_wind_power = simulation_state.wind_turbines(1).power_setpoint;

end

% Dispatch solar to deliver AC power
% 
% inputs
% ------
% simulation_state : object holding current state of simulation
% simulation_parameters : object holding current parameters of simulation
% load : AC power requested from solar
% inv_efficiency : the DC->AC efficiency of the rectifier
%
% outputs
% -------
% avail_solar_ac : AC solar power available for dispatch
% simulation_state : object holding current state of simulation
%
function [avail_solar_ac, simulation_state] = dispatch_solar(simulation_state, simulation_parameters, load, inv_efficiency)

    simulation_state.pvs(1).power_setpoint = 0;
    if simulation_parameters.has_pv == true
        simulation_state.pvs(1).power_setpoint = simulation_state.pvs(1).power_available;
    end
    avail_solar_dc = simulation_state.pvs(1).power_setpoint;
    avail_solar_ac = 0;
    if simulation_parameters.has_converter == true
      avail_solar_ac = min(simulation_parameters.converters(1).inverter_capacity, avail_solar_dc * inv_efficiency/100);
    end

end  

function [simulation_state, matlab_simulation_variables] = MatlabDispatchWindplus(simulation_parameters, simulation_state, matlab_simulation_variables)
%%
% define a small enough number to account for accuracy difference

      
  % the matrix
  parameters = zeros(3,14);

      
% we don't have dc load in green case, se    all related state variable to 0 
  simulation_state = ignore_dc(simulation_state);

% define intermediate variables that we do not want to see in model output
  battery_max_discharge_power = 0; % AC this one is unecessary since we will only compare this value with others when we don't have excess solar
  battery_max_charge_power = 0;    % DC
  generator_max_possible_output_from_load_and_battery = 0; % AC
  
% extract rectifier and inverter efficiency
  % PPHW: aren't these defined in HOMER?
  if simulation_parameters.has_battery == true
      rect_efficiency = 90;
      inv_efficiency = 95;
  else
    rect_efficiency = 1;
    inv_efficiency = 1;
  end
  simulation_parameters.converters(1).rectifier_efficiency = rect_efficiency;
  simulation_parameters.converters(1).inverter_efficiency = inv_efficiency;

% initialize battery and rectifier system
  simulation_state.batteries(1).power_setpoint = 0;
  simulation_state.converters(1).rectifier_power_input = 0;
  simulation_state.converters(1).rectifier_power_output = 0;

% initialize inverter system
  simulation_state.converters(1).inverter_power_output = 0;
  simulation_state.converters(1).inverter_power_input = 0; 

%%  
% step 1: use wind first, and then PV

  load_requested = simulation_state.ac_bus.load_requested;

  %%% WIND ENERGY
  %
  % determine available wind
  avail_wind_power = dispatch_wind(simulation_state, simulation_parameters, load_requested);

  % serve the load with wind
  dispatched_wind_power = min(load_requested, avail_wind_power);
  net_load_after_wind = load_requested - dispatched_wind_power;
  excess_wind = avail_wind_power - dispatched_wind_power;
  wind_to_batteries = 0;

  % charge batteries with excess wind
  if (excess_wind > 0 )
    net_load_after_wind = 0;

    if simulation_parameters.has_converter == true && simulation_parameters.has_battery == true
      wind_to_batteries, simulation_state = charge_batteries_ac(simulation_state, simulation_parameters, excess_wind, rect_efficiency);
    end

    excess_wind = excess_wind - wind_to_batteries;

  end

 
  %%% SOLAR PV ENERGY
  %
  % determine available solar

  % dispatch solar power to DC network
  avail_solar_ac = dispatch_solar(simulation_state, simulation_parameters, net_load_after_wind, inv_efficiency);

  % serve load with solar
  dispatched_solar_power = min(net_load_after_wind, avail_solar_ac);
  simulation_state = increment_inverter_load(simulation_state, dispatched_solar_power, inv_efficiency);

  net_load_after_solar = net_load_after_wind - dispatched_solar_power;
  excess_solar_ac = avail_solar_ac - dispatched_solar_power;
  excess_solar_dc = excess_solar_ac / (inv_efficiency/100);
  solar_to_batteries = 0;

  % charge batteries with excess solar
  if (excess_solar_ac > 0)

    if (simulation_parameters.has_battery == true)
        solar_to_batteries, simulation_state = charge_batteries_dc(simulation_state, simulation_parameters, excess_solar_dc)
        excess_solar_dc = excess_solar_dc - solar_to_batteries;
        excess_solar_ac = excess_solar_dc * inv_efficiency/100;
    end

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

for option = 1,3
    dispatched_battery_ac = 0;
    battery_charge_power = 0
    dispatched_generator = 0;
    excess_generator = 0;
    ac_to_batteries = 0;
    remaining_load = net_load_after_solar;

    %% option 1: dispatch batteries first
    if (option == 1)
        avail_battery_ac = dispatch_batteries(simulation_state, simulation_parameters, remaining_load);
    
        % serve load with solar
        dispatched_battery_ac = min(remaining_load, avail_battery_ac);
    end

    % option 1 - reduce load; option 2 & 3 - no effect
    remaining_load = remaining_load - dispatched_battery_ac;

    %% option 3: determine available battery charging
    if (option == 3)
        battery_charge_power = get_battery_ac_charge_power(simulation_state, simulation_parameters, max_load, rect_efficiency);
    end

    generator_demand = remaining_load + battery_charge_power;

    %% dispatch generator next
    if ( generator_demand > eps)
        avail_generator_power = dispatch_generator(simulation_state, simulation_parameters, generator_demand);

        % serve load with generator
        dispatched_generator = min(remaining_load, avail_generator_power);
        excess_generator = avail_generator_power - dispatched_generator;
    end

    remaining_load = remaining_load - dispatched_generator;

    %% dispatch batteries after generator (option 2 & 3)
    if (remaining_load > eps)
        avail_battery_ac = dispatch_batteries(simulation_state, simulation_parameters, remaining_load);
    
        % serve load with solar
        dispatched_battery_ac = min(remaining_load, avail_battery_ac);
    end

    remaining_load = remaining_load - dispatched_battery_ac;

    if (excess_generator > eps)
        ac_to_batteries = get_battery_ac_charge_power(simulation_state, simulation_parameters, excess_generator, rect_efficiency);
        excess_generator = excess_generator - ac_to_batteries;
    end

    net_discharge_ac = dispatched_battery_ac - ac_to_batteries;
    net_charge_ac = 0;
    if net_discharge_ac < 0;
        net_charge_ac = -net_discharge_ac;
        net_discharge_ac = 0;

    net_charge_dc = net_charge_ac * (rect_efficiency/100);
    net_discharge_dc = net_discharge_ac / (inv_efficiency/100);


    parameters(option,generator_power_setpoint) = avail_generator_power;
    % battery net charge equal to step 1
    parameters(option,battery_power_setpoint) = simulation_state.batteries(1).power_setpoint + net_charge_dc - net_discharge_dc;
    % inverter output equal to step 1
    parameters(option,inverter_power_output) = simulation_state.converters(1).inverter_power_output + net_discharge_ac;
    % inverter input in dc adjusted by inverter efficiency
    parameters(option,inverter_power_input) = parameters(option, inverter_power_output) / (inv_efficiency/100);
    % rectifier input set to step 1
    parameters(option,rectifier_power_input) = simulation_state.converters(1).rectifier_power_input + net_charge_ac;
    % rectifier output set to step 1
    parameters(option,rectifier_power_output) = simulation_state.converters(1).rectifier_power_input * (rect_efficiency/100);
    % primary load served             dispatched_battery_dc = dispatched_battery_ac / (inv_efficiency/100);

    parameters(option,primary_load_served) = dispatched_wind_power + dispatched_solar_power + dispatched_battery_ac + dispatched_generator;
    % ac bus excess electricity
    parameters(option,ac_bus_excess_electricity) = excess_solar_ac + excess_wind + excess_generator;
    % ac bus load served
    parameters(option,ac_bus_load_served) = parameters(option,primary_load_served);
    % ac bus operating capacity requested: refelect requested load reserve
    parameters(option,ac_bus_operating_capacity_requested) = parameters(option,primary_load_served) * ... 
                (1 + simulation_parameters.operating_reserve.timestep_requirement/100);
    % ac bus unmet load
    parameters(option,ac_bus_unmet_load) = ...
        simulation_state.ac_bus.load_requested - parameters(option,primary_load_served);
    % ac bus capacity shortage
    parameters(option,ac_bus_operating_capacity_served) = parameters(option,ac_bus_load_served) + ...
                                                          parameters(option,ac_bus_excess_electricity);
    parameters(option,ac_bus_operating_capacity_served) = min( parameters(option,ac_bus_operating_capacity_requested), ...
                                                            parameters(option,ac_bus_operating_capacity_served) );
end
 %%
 
 
parameters(:,marginal_cost) = ...
    (matlab_simulation_variables.generator_fuel_cost * parameters(:,generator_power_setpoint))/matlab_simulation_variables.net_load ...
  + (parameters(:,generator_power_setpoint)>0) * matlab_simulation_variables.generator_OM / matlab_simulation_variables.net_load ...
  + matlab_simulation_variables.electricity_price * parameters(:,ac_bus_unmet_load)/matlab_simulation_variables.net_load ...
  + simulation_state.batteries(1).energy_cost * parameters(:,inverter_power_output)/matlab_simulation_variables.net_load ...      % 0 if no batteries
  + simulation_parameters.batteries(1).wear_cost * parameters(:,inverter_power_output)/matlab_simulation_variables.net_load ...   % 0 if no batteries
  + simulation_parameters.batteries(1).wear_cost * parameters(:,rectifier_power_input)/matlab_simulation_variables.net_load  ...  % 0 if no batteries
  + matlab_simulation_variables.electricity_price * parameters(:,inverter_power_output)/matlab_simulation_variables.net_load ...  % 0 if no batteries
  - matlab_simulation_variables.electricity_price * parameters(:,rectifier_power_input)/matlab_simulation_variables.net_load;     % 0 if no batteries
    
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
