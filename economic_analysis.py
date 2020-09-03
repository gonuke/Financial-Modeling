import numpy as np
import yaml
import argparse
import pandas as pd
import datetime
import statistics
import math

MW2KW = 1000
HrPerYr = 8760
HrPerDay = 24
DaysOfPowerPerYear = 365

def select_lng(Scenario, generation_type_one, generation_type_two, my_data):
    if Scenario == 'Scenario4' and generation_type_one == 'NaturalGas':
        my_data['generation_data']['NaturalGas']['Best']['RealFuelCost']= my_data['model_assumptions']['LNG']['Best']
        my_data['generation_data']['NaturalGas']['Median']['RealFuelCost']= my_data['model_assumptions']['LNG']['Median']
        my_data['generation_data']['NaturalGas']['Worst']['RealFuelCost']= my_data['model_assumptions']['LNG']['Worst']
    elif (Scenario in ('Scenario3', 'Scenario4') and generation_type_two == 'NaturalGas'):
        my_data['generation_data']['NaturalGas']['Best']['RealFuelCost']= my_data['model_assumptions']['LNG']['Best']
        my_data['generation_data']['NaturalGas']['Median']['RealFuelCost']= my_data['model_assumptions']['LNG']['Median']
        my_data['generation_data']['NaturalGas']['Worst']['RealFuelCost']= my_data['model_assumptions']['LNG']['Worst']
    return my_data

def pmt_total(Scenario, generation_type_one_data, generation_type_two_data, interest):
    return evaluate_generation_costs_utility(Scenario)+evaluate_generation_costs_one(Scenario, generation_type_one_data, interest)+evaluate_generation_costs_two(Scenario, generation_type_two_data, interest)
    
def evaluate_generation_costs_utility(Scenario):
        
        UtilityRate = my_data['model_assumptions']['UtilityRate']
        UtilityPower = my_data['scenario_assumptions'][Scenario]['UtilityPower']
        if Scenario == 'Scenario2':
            return (UtilityRate*UtilityPower*MW2KW*HrPerYr)+(UtilityRate*UtilityPower*MW2KW*HrPerDay*my_data['model_assumptions']['DaysOfBackupPower'])
        else:
            return UtilityRate*UtilityPower*MW2KW*HrPerYr
    
def npv_factor(interest, periods):
    
    return ((1+interest)**periods-1)/(interest*(1+interest)**periods)
    
def evaluate_generation_costs_one(Scenario, generation_type_one_data, interest):

        required_capacity =  my_data['scenario_assumptions'][Scenario]['PrimaryPower'] / generation_type_one_data['CapacityFactor']
        total_annual_generation = my_data['scenario_assumptions'][Scenario]['PrimaryPower']*DaysOfPowerPerYear*HrPerDay*MW2KW
        effective_refurb_interest = (1+interest)**generation_type_one_data['CoreLife']-1
        number_of_refurbs = generation_type_one_data['AssetLife']//generation_type_one_data['CoreLife']
        
        npv_capital = required_capacity * generation_type_one_data['CapitalCost']*MW2KW
        npv_fuel = npv_factor(interest, generation_type_one_data['AssetLife'])*generation_type_one_data['RealFuelCost'] *total_annual_generation
        npv_om = npv_factor(interest, generation_type_one_data['AssetLife'])*((generation_type_one_data['FixedOMCost'] * my_data['scenario_assumptions'][Scenario]['PrimaryPower']*MW2KW) + (generation_type_one_data['VariableOMCost'] * total_annual_generation))
        npv_decommission = npv_factor(interest, generation_type_one_data['AssetLife'])*generation_type_one_data['DecommissionCost']*required_capacity*MW2KW*HrPerYr
        npv_refurb = npv_factor(effective_refurb_interest, number_of_refurbs)*generation_type_one_data['RefurbishmentCost']
        
        return -np.pmt(interest, generation_type_one_data['AssetLife'], npv_capital+npv_om+npv_decommission+npv_refurb+npv_fuel)

def evaluate_generation_costs_two(Scenario, generation_type_two_data, interest):

        total_annual_generation = my_data['scenario_assumptions'][Scenario]['BackupPower']*HrPerDay*MW2KW*my_data['model_assumptions']['DaysOfBackupPower']
        
        npv_capital = my_data['scenario_assumptions'][Scenario]['BackupPower'] * generation_type_two_data['CapitalCost']*MW2KW
        npv_reserve = my_data['model_assumptions']['DaysOfResilience']*generation_type_two_data['RealFuelCost']*my_data['scenario_assumptions'][Scenario]['BackupPower']*MW2KW*HrPerYr/DaysOfPowerPerYear
        npv_om = npv_factor(interest, generation_type_two_data['AssetLife'])*((generation_type_two_data['FixedOMCost'] * my_data['scenario_assumptions'][Scenario]['BackupPower']*MW2KW) + (generation_type_two_data['VariableOMCost'] * total_annual_generation))
        npv_fuel = npv_factor(interest, generation_type_two_data['AssetLife'])*generation_type_two_data['RealFuelCost'] *total_annual_generation
    
        return -np.pmt(interest, generation_type_two_data['AssetLife'], npv_capital+npv_om+npv_reserve+npv_fuel)
    
def load_inputs():

    with open('inputs.yml', 'r') as yaml_file:
        inputs = yaml.load(yaml_file, Loader=yaml.FullLoader)

    return inputs

def initialize_real_fuel_costs(my_data, fuel_type):
    if fuel_type == 'std':
     for generation_type, generation_type_data in my_data['generation_data'].items():
        for generation_variation in generation_type_data: 
               my_data['generation_data'][generation_type][generation_variation]['RealFuelCost'] = my_data['generation_data'][generation_type][generation_variation]['FuelCost']
    elif fuel_type == 'alt':
        for generation_type, generation_type_data in my_data['generation_data'].items():
            for generation_variation in generation_type_data: 
               my_data['generation_data'][generation_type][generation_variation]['RealFuelCost'] = my_data['generation_data'][generation_type][generation_variation]['AltFuelCost']* my_data['generation_data'][generation_type][generation_variation]['HeatRate']
    else:
        print("error enter proper fuel cost")
    return my_data

def Mean(x):
    return statistics.mean(x)
def StandardDeviation(x):
    return statistics.stdev(x)
def StandardError(x, iterations):
    return StandardDeviation(x)/math.sqrt(iterations)
def NinetyFivePercentCIHalfWidth(x, iterations):
    return 1.96*StandardError(x,iterations)
def UpperCILimit(x, iterations):
    return Mean(x) + NinetyFivePercentCIHalfWidth(x, iterations)
def LowerCILimit(x, iterations):
    return Mean(x) - NinetyFivePercentCIHalfWidth(x, iterations)

def monte_carlo_analysis(my_data, case_list, iterations):
    OneNuclear = []
    OneDiesel = []
    OneNaturalGas = []
    TwoNuclear= []
    TwoDiesel = []
    TwoNaturalGas = []
    ThreeNuclear = []
    ThreeDiesel = []
    ThreeNaturalGas = []
    FourNuclear = []
    FourDiesel = []
    FourNaturalGas = []
    ScenarioList = [OneNuclear, OneDiesel, OneNaturalGas , TwoNuclear, TwoDiesel , TwoNaturalGas,  ThreeNuclear ,ThreeDiesel ,ThreeNaturalGas,FourNuclear ,FourDiesel ,FourNaturalGas]
    for j in range (1, iterations+1):
        Monte_Carlo_List = []
        Monte_Carlo_List = monte_carlo_distribution(my_data, case_list)
        OneNuclear.append(Monte_Carlo_List[0])
        OneDiesel.append(Monte_Carlo_List[1])
        OneNaturalGas.append(Monte_Carlo_List[2])
        TwoNuclear.append(Monte_Carlo_List[3])
        TwoDiesel.append(Monte_Carlo_List[4])
        TwoNaturalGas.append(Monte_Carlo_List[5])
        ThreeNuclear.append(Monte_Carlo_List[6])
        ThreeDiesel.append(Monte_Carlo_List[7])
        ThreeNaturalGas.append(Monte_Carlo_List[8])
        FourNuclear.append(Monte_Carlo_List[9])
        FourDiesel.append(Monte_Carlo_List[10])
        FourNaturalGas.append(Monte_Carlo_List[11])
        if j == .25*iterations or j == .5*iterations or j == .75*iterations or j== .9*iterations:
            print("Progress: "+"%{:.0f}".format(100*j/iterations),"Iteration #: "+"{:.0f}".format(j))
    for x in ScenarioList:
        Mean(x)
        StandardDeviation(x)
        StandardError(x, iterations)
        NinetyFivePercentCIHalfWidth(x, iterations)
        UpperCILimit(x, iterations)
        LowerCILimit(x, iterations)
        Results.append([Mean(x), StandardDeviation(x), StandardError(x, iterations), NinetyFivePercentCIHalfWidth(x, iterations), UpperCILimit(x, iterations), LowerCILimit(x, iterations), iterations])
    dfResults = pd.DataFrame(Results, columns = [ 'Mean', 'Standard Deviation','Standard Error', 'NinetyFive% CI HW','Upper CI Limit', 'Lower CI Limit', '# of iterations'])
    dfResults.insert(0,'Scenario & tech combo', ['Scenario1 None Nuclear','Scenario1 None Diesel','Scenario1 None NaturalGas','Scenario2 Nuclear None','Scenario2 Diesel None','Scenario2 NaturalGas None','Scenario3 Nuclear Diesel','Scenario3 Diesel NaturalGas','Scenario3 NaturalGas Diesel','Scenario4 Nuclear Diesel','Scenario4 Diesel NaturalGas','Scenario4 NaturalGas Diesel'], True)
    pd.set_option('display.max_columns', None)
    pd.set_option('display.max_rows', None)
    dfResults['Mean'] = dfResults.apply(lambda x: "${:,.2f}".format(x['Mean']), axis=1)
    dfResults['Standard Deviation'] = dfResults.apply(lambda x: "{:,.2f}".format(x['Standard Deviation']), axis=1)
    dfResults['Standard Error'] = dfResults.apply(lambda x: "${0:,.2f}".format(x['Standard Error']), axis=1)
    dfResults['NinetyFive% CI HW'] = dfResults.apply(lambda x: "${0:,.2f}".format(x['NinetyFive% CI HW']), axis=1)
    dfResults['Upper CI Limit'] = dfResults.apply(lambda x: "{0:,.2f}".format(x['Upper CI Limit']), axis=1)
    dfResults['Lower CI Limit'] = dfResults.apply(lambda x: "{0:,.2f}".format(x['Lower CI Limit']), axis=1)
    print(dfResults)        
        
def monte_carlo_distribution(my_data, case_list):
    Results = []
    for Scenario, cases in case_list.items():
        Scenario == 'Scenario1'
        for generation_type_one, generation_type_two in cases:
            my_data = select_lng(Scenario,generation_type_one, generation_type_two, my_data)
            Sensitive_list = list(my_data['generation_data']['Nuclear']['Median'].keys())
            Sensitive_list.remove('FuelCost')
            Sensitive_list.remove('AltFuelCost')
            Sensitive_list.remove('HeatRate')
            generation_type_one_data = dict(my_data['generation_data'][generation_type_one]['Median'])
            generation_type_two_data = dict(my_data['generation_data'][generation_type_two]['Median'])
            for x in Sensitive_list:
                for z in [generation_type_one,generation_type_two]:
                    if z == generation_type_one and my_data['generation_data'][z]['Worst'][x] < my_data['generation_data'][z]['Best'][x]:
                        generation_type_one_data[x] = np.random.triangular(my_data['generation_data'][z]['Worst'][x],my_data['generation_data'][z]['Median'][x],my_data['generation_data'][z]['Best'][x])
                    elif z == generation_type_one and my_data['generation_data'][z]['Worst'][x] > my_data['generation_data'][z]['Best'][x]:
                        generation_type_one_data[x] = np.random.triangular(my_data['generation_data'][z]['Best'][x],my_data['generation_data'][z]['Median'][x],my_data['generation_data'][z]['Worst'][x])
                    elif z == generation_type_one and my_data['generation_data'][z]['Worst'][x] == my_data['generation_data'][z]['Best'][x]:
                        generation_type_one_data[x] = np.random.uniform(my_data['generation_data'][z]['Best'][x],my_data['generation_data'][z]['Worst'][x])
                    elif z == generation_type_two and my_data['generation_data'][z]['Worst'][x] < my_data['generation_data'][z]['Best'][x]:
                        generation_type_two_data[x] = np.random.triangular(my_data['generation_data'][z]['Worst'][x],my_data['generation_data'][z]['Median'][x],my_data['generation_data'][z]['Best'][x])
                    elif z == generation_type_two and my_data['generation_data'][z]['Worst'][x] > my_data['generation_data'][z]['Best'][x]:
                        generation_type_two_data[x] = np.random.triangular(my_data['generation_data'][z]['Best'][x],my_data['generation_data'][z]['Median'][x],my_data['generation_data'][z]['Worst'][x])
                    else:
                        generation_type_two_data[x] = np.random.uniform(my_data['generation_data'][z]['Best'][x], my_data['generation_data'][z]['Worst'][x])
            Results.append( 
                            pmt_total(Scenario, generation_type_one_data,
                                      generation_type_two_data, interest))
    return Results

def sensitivity_analysis(my_data, case_list):
    interest_rates = list(my_data['model_assumptions']['SensitivityInterestRates'])
    for Scenario, cases in case_list.items():
        for generation_type_one, generation_type_two in cases:
            my_data = select_lng(Scenario,generation_type_one, generation_type_two, my_data)
            Sensitive_list = list(my_data['generation_data']['Nuclear']['Median'].keys())
            Sensitive_list.remove('FuelCost')
            Sensitive_list.remove('AltFuelCost')
            Sensitive_list.remove('HeatRate')
            for x in Sensitive_list:
                for y in ['Best','Median','Worst']:
                    for z in [generation_type_one, generation_type_two]:
                        for interest in interest_rates:
                            generation_type_one_data = dict(my_data['generation_data'][generation_type_one]['Median'])
                            generation_type_two_data = dict(my_data['generation_data'][generation_type_two]['Median'])
                            if z == generation_type_one:
                                generation_type_one_data[x] = my_data['generation_data'][z][y][x]
                            else:
                                generation_type_two_data[x] = my_data['generation_data'][z][y][x]
                            Results.append([Scenario, generation_type_one, generation_type_two, interest, x,y,z,
                                            pmt_total(Scenario, generation_type_one_data,
                                            generation_type_two_data, interest)])
    dfResults = pd.DataFrame(Results, columns = ['Scenario', 'Power Type','Backup', 'interest','Sensitivity Variable','B/M/W','Sensitivity Technology','Annual Payment'])
    dfResults['Annual Payment'] = dfResults.apply(lambda x: "{0:,.2f}".format(x['Annual Payment']), axis=1)
    dfResults.drop(dfResults[dfResults['Sensitivity Technology'] == 'None'].index, inplace = True)
    writer_orig = pd.ExcelWriter('SensitivityList_'+datetime.datetime.now().strftime("%b")+datetime.datetime.now().strftime("%d")+datetime.datetime.now().strftime("%y")+datetime.datetime.now().strftime("%H")+datetime.datetime.now().strftime("%M")+'.xlsx', engine='xlsxwriter')
    dfResults.to_excel(writer_orig, index=False, sheet_name='Sensitivity Inputs')
    writer_orig.save()
    
def main_code(my_data, case_list, 
              generation_variation_nuclear,
              generation_variation_naturalgas,
              generation_variation_diesel):
    generation_variation_none = 'Median'
    generation_variation = { 'Nuclear': generation_variation_nuclear,
                            'Diesel': generation_variation_diesel, 
                            'NaturalGas': generation_variation_naturalgas, 
                            'None': generation_variation_none
                            }
    for Scenario, cases in case_list.items():
        for generation_type_one, generation_type_two in cases:
            my_data = select_lng(Scenario,generation_type_one, generation_type_two, my_data)
            Results.append([Scenario, generation_type_one, generation_type_two, interest, 
                            pmt_total(Scenario, my_data['generation_data'][generation_type_one][generation_variation[generation_type_one]],
                                      my_data['generation_data'][generation_type_two][generation_variation[generation_type_two]], interest)])

    dfResults = pd.DataFrame(Results, columns = ['Scenario', 'Power Type','Backup', 'interest','Annual Payment'])
    dfResults['Annual Payment'] = dfResults.apply(lambda x: "{0:,.2f}".format(x['Annual Payment']), axis=1)
    print(dfResults)


def read_args():

    default_interest_rate = 0.02

    parser = argparse.ArgumentParser()

    subparsers = parser.add_subparsers()

    parser_mc = subparsers.add_parser('monte_carlo')
    parser_sens = subparsers.add_parser('sensitivity')
    parser_single = subparsers.add_parser('single')

    for subparser in [parser_mc, parser_single]:
        subparser.add_argument('-i', '--interest_rate', type=float,
                            help="interest rate to use for this analysis (default: {:.2f})".format(default_interest_rate),
                            default=default_interest_rate)
    default_samples = 20
    parser_mc.add_argument('-N', '--num_samples', type=int,
                            help="number of Monte Carlo samples (default: {:d})".format(default_samples),
                            default=default_samples)
    parser_mc.set_defaults(func=run_mc)
    

    parser_sens.set_defaults(func=run_sensitivity)
    
    case_choices = ['Best', 'Median', 'Worst']
    parser_single.add_argument('--nuclear-case',choices=case_choices,
                                help="Which case to use for nuclear costs",
                                default='Median')
    parser_single.add_argument('--gas-case',choices=case_choices,
                                help="Which case to use for natural gas costs",
                                default='Median')
    parser_single.add_argument('--diesel-case',choices=case_choices,
                                help="Which case to use for diesel costs",
                                default='Median')
    parser_single.set_defaults(func=run_single)

    for subparser in [parser_mc, parser_sens, parser_single]:
        subparser.add_argument('-f', '--fuelcost_type', choices=['std', 'alt'],
                                default='std')
        subparser.add_argument('filename', help="YAML file with economic data")

    return parser.parse_args()

def init(fuelcost_type):

    my_data = load_inputs()
    my_data = initialize_real_fuel_costs(my_data, fuelcost_type)

    case_list = {
        'Scenario1': list(zip(['None','None','None'], ['Nuclear','Diesel','NaturalGas'])), 
        'Scenario2': list(zip(['Nuclear','Diesel','NaturalGas'],['None','None','None'])),
        'Scenario3': list(zip(['Nuclear','Diesel','NaturalGas'], ['Diesel','NaturalGas','Diesel'])),
        'Scenario4': list(zip(['Nuclear','Diesel','NaturalGas'], ['Diesel','NaturalGas','Diesel']))
            }

    return my_data, case_list

def run_mc(args):

    my_data, case_list = init(args.fuelcost_type)

    interest = args.interest_rate
    monte_carlo_analysis(my_data, case_list, args.num_samples)

def run_sensitivity(args):

    my_data, case_list = init(args.fuelcost_type)

    sensitivity_analysis(my_data, case_list)

def run_single(args):

    my_data, case_list = init(args.fuelcost_type)

    interest = args.interest_rate
    main_code(my_data, case_list, args.nuclear_case, args.gas_case, args.diesel_case)


if __name__ == "__main__":
  args = read_args()

  Results = []

  args.func(args)

