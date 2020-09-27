function myErrs = MatlabEndSimulation(simulation_parameters, matlab_simulation_variables)
myErrs.simulation_errors = {};
myErrs.simulation_warnings = {};

% if simulation_parameters.emissions.use_max_emissions_CO && matlab_simulation_variables.gen1_CO > simulation_parameters.emissions.max_emissions_CO
%     myErrs.simulation_errors = [myErrs.simulation_errors {'Too much carbon monoxide from generator 1.'}];
% end
end
