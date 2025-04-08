############################################
#### Define paths
############################################

println("Starting full script timer...")
@time global_start_time = time()

const PATH_global = "/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/"      

const PATH_data = PATH_global*"/Data/Core/"
const PATH_source = PATH_global*"/julia_codes/"
#push!(LOAD_PATH, string(PATH_source, "source/"))

###########################################
#### Load necessary packages
############################################

using JuMP, Gurobi, ParameterJuMP
using DataFrames, CSV, JLD2, Missings, XLSX, JLD
using Statistics, Random
using PyPlot
using Dates
#using Distributed, Parallelism

###########################################
#### Include julia files with functions
############################################

include("read_system_tables.jl")
include("eno_model.jl")
include("handle_models.jl")

###########################################
#### Define constants
############################################

const CO2PRICE = 6.2327
const T_hour = 24
const T_15 = 96
const VOLL = 3000
const target_countries = ["Croatia","Austria","Slovenia"]#,"Hungary","Romania","Slovakia","Czech","Switzerland"#,"Denmark","Poland","Luxemburg","Germany","Netherland","France","Belgium"]
all_buses = CSV.read(joinpath(PATH_data, "Buses.csv"), DataFrame)
all_lines = CSV.read(joinpath(PATH_data, "Lines.csv"), DataFrame)
filtered_buses = filter(row -> row.Country ∈ target_countries, all_buses)
const Ref_hub = filtered_buses[1:1, :]
const Buses = filtered_buses[2:end, :] 
prefixes = Set(split.(Buses.Bus, "_") .|> first)
const Lines = filter(r -> (split(r.FromBus, "_")[1] ∈ prefixes && split(r.ToBus, "_")[1] ∈ prefixes), all_lines)

include("Ptdf_calculator_2.jl")

const map_t, inv_map_t = create_min_map(T_15)
const DAY_TYPES = ["SpringWD", "SpringWE", "SummerWD", "SummerWE", "AutumnWD", "AutumnWE", "WinterWD", "WinterWE"]

###########################################
#### Define run parameters
############################################

solver_name = "Gurobi"
day_type = "SpringWD"

############################################
#### Load data 
############################################

const generators, generator_planned_outages, generators_RE, loads,
dynamic_profiles, determ_profile_rates, stoch_profile_rates,
buses, heat_rate_curves, fuel_price, lines = read_system_tables(PATH_data)

const zones = Buses
const PTDF_zones = zones

const generators_id_per_zone, generators_id = get_generators_id(generators, generators_RE, buses, zones)
const PTDF_data , PTDF_df = load_ptdf_data(PATH_data, Ref_hub)

include("flow_calculator.jl")

#=println(generators_id_per_zone["conventional"]["Cro_17"])
println(generators_id_per_zone["renewable"]["Cro_17"])
println(generators_id_per_zone["conventional"]["Cro_11"])
println(generators_id_per_zone["renewable"]["Cro_11"])=#

############################################
#### Create models 
############################################

gurobi_env = Gurobi.Env()

eno_model = define_solver(solver_name, gurobi_env)
attach_energy_only_clearing_model!(eno_model, day_type)
attach_PTDF_model!(eno_model, PTDF_data::Dict)

eno_lp_model = define_solver(solver_name, gurobi_env)
attach_energy_only_clearing_model!(eno_lp_model, day_type)
attach_PTDF_model!(eno_lp_model, PTDF_data::Dict)
get_lp_model(eno_lp_model) 

unfix_model(eno_lp_model)
set_up_loads!(eno_model, day_type)
set_up_loads!(eno_lp_model, day_type)

set_up_renewables!(eno_model,  day_type, "average")
set_up_renewables!(eno_lp_model,  day_type, "average")

# Set up planned outage / Ignore for now 
#set_up_planned_outages!(eno_model, day_type)
#set_up_planned_outages!(eno_lp_model, day_type)

############################################
#### Solve models 
############################################

println("Solving eno_model...")
@time optimize!(eno_model)
println("Termination status: ", termination_status(eno_model))
println("Objective value: ", objective_value(eno_model))
println("Variables in eno_model: ", num_variables(eno_model))
println("Constraints in eno_model: ", num_constraints(eno_model; count_variable_in_set_constraints=true))

#=println(dual.(eno_model[:load_balance_constraint])["Ger_27", 75])
println(dual.(eno_model[:load_balance_constraint])["Ger_10", 75])=#
#=for time in 1:T_hour
    for t in ((time - 1) * 4 + 1):(time * 4) 
        println(value(eno_model[:p_re]["Cro_11", t]))
    end
    readline()
end
exit()=#

fix_model(eno_model, eno_lp_model)

println("Solving eno_lp_model...")
@time optimize!(eno_lp_model)
println("Variables in eno_lp_model: ", num_variables(eno_lp_model))
println("Constraints in eno_lp_model: ", num_constraints(eno_lp_model; count_variable_in_set_constraints=true))

println("Solution completed")

#Store output

output=get_outputs_df(eno_model, eno_lp_model) 

results_path = "/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/results/"

for (key, value) in output
    filename = joinpath(results_path, "$key.csv")
    CSV.write(filename, value)
    println("Saved DataFrame under key '$key' to file '$filename'")
end

include("flow_calculator.jl")
calculate_and_save_flows(PTDF_df,Lines,eno_model,"/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/results")

include("Plots.jl")

############################################
#### Τελικός χρόνος
############################################

println("--- SCRIPT FINISHED ---")
total_time = time() - global_start_time
println("Total execution time: $(round(total_time, digits=3)) seconds") 