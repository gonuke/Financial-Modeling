function [myErr, matlab_simulation_variables] = MatlabStartSimulation(simulation_parameters)
myErr.error_description = '';
myErr.severity_code = '';

%Initialize user-defined simulation variables. We can use these throughout the simulation
%for dispatch decisions or to generate errors at the end of the simulation.
%matlab_simulation_variables.total_energy_test = 0;
%matlab_simulation_variables.gen1_CO = 0;


% reactor fuel cost in $/kWh
% a fuel cost of [$/kWh] should remain constant; it would just be a conversion from the standard fuel cost in [$/kg] by dividing by the lower heating value (MJ/kg] and converting to [kWh]
% low cost
% fuel price, $/kg
% low
generator_unit_fuel_cost = 6030;
% median
%matlab_simulation_variables.generator_unit_fuel_cost = 15400;
% lhv, MJ/kg
generator_lhv = 12960000;
% a conversion from MJ to kWh
conversion_mj_kg = 0.2778;
% cost, $/kWh
matlab_simulation_variables.generator_fuel_cost = ...
    generator_unit_fuel_cost / generator_lhv / conversion_mj_kg;
% median cost

% reactor O&M cost in $/op.hr
% low cost
matlab_simulation_variables.generator_OM = 14.61;
% median cost
% matlab_simulation_variables.generator_OM = 33.45;

% set a reactor ramp rate in %/min
% matlab_simulation_variables.generator_ramp_rate = 5;

% set a variable to capture net load
matlab_simulation_variables.net_load = 0;

% set a variable to capture value of energy in $/kWh
matlab_simulation_variables.electricity_price = 0.06;

end