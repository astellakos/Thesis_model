############################################
#### Define paths
############################################

println("Starting full script timer...")
time_info = @timed begin

model_start_time = time()

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
const target_countries = ["Austria"]
# ISO country codes για ασφαλή naming
const ISO_CODES = Dict("Germany" => "DE", "Austria" => "AT", "Belgium" => "BE", "France" => "FR", "Netherlands" => "NL", "Netherland" => "NL", "Luxembourg" => "LU", "Luxemburg" => "LU", "Denmark" => "DK", "Poland" => "PL", "Switzerland" => "CH", "Czech" => "CZ", "Slovakia" => "SK", "Slovenia" => "SI", "Hungary" => "HU", "Croatia" => "HR", "Romania" => "RO")

# Δημιουργία path βάσει χωρών
country_tag = join([get(ISO_CODES, c, c[1:min(end, 3)]) for c in target_countries], "_")
results_alt_path = joinpath("/Users/alexiostellakos/Desktop/Cases", country_tag)
if !isdir(results_alt_path)
    mkpath(results_alt_path)
end
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

############################################
#### Create models 
############################################

gurobi_env = Gurobi.Env()

eno_model = define_solver(solver_name, gurobi_env)
attach_energy_only_clearing_model!(eno_model, day_type)
attach_PTDF_model!(eno_model, PTDF_data::Dict)

#=eno_lp_model = define_solver(solver_name, gurobi_env)
attach_energy_only_clearing_model!(eno_lp_model, day_type)
attach_PTDF_model!(eno_lp_model, PTDF_data::Dict)
get_lp_model(eno_lp_model) 

unfix_model(eno_lp_model)=#
set_up_loads!(eno_model, day_type)
#set_up_loads!(eno_lp_model, day_type)

set_up_renewables!(eno_model,  day_type, "average")
#set_up_renewables!(eno_lp_model,  day_type, "average")

# Set up planned outage / Ignore for now 
#set_up_planned_outages!(eno_model, day_type)
#set_up_planned_outages!(eno_lp_model, day_type)

########################################################
#### Report model size before optimisation (count‑only)
########################################################
println("Variables in eno_model (pre-solve): ",
        num_variables(eno_model))
println("Constraints in eno_model (pre-solve): ",
        num_constraints(eno_model; count_variable_in_set_constraints = true))

if get(ENV, "COUNT_ONLY", "0") == "1"
    println("COUNT_ONLY flag detected - terminating script before optimisation.")
    exit()
end

############################################
#### Solve models 
############################################

println("Solving eno_model...")

#=set_optimizer_attribute(eno_model, "Method", 2)
set_optimizer_attribute(eno_model, "Crossover", 0)
=#
@time optimize!(eno_model)
println("Termination status: ", termination_status(eno_model))
println("Objective value: ", objective_value(eno_model))
model_solve_time = time() - model_start_time
println("Variables in eno_model: ", num_variables(eno_model))
println("Constraints in eno_model: ", num_constraints(eno_model; count_variable_in_set_constraints=true))
#=fix_model(eno_model, eno_lp_model)

println("Solving eno_lp_model...")
@time optimize!(eno_lp_model)
println("Variables in eno_lp_model: ", num_variables(eno_lp_model))
println("Constraints in eno_lp_model: ", num_constraints(eno_lp_model; count_variable_in_set_constraints=true))

println("Solution completed")=#

#Store output

output = get_outputs_df(eno_model, nothing)

results_path = "/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/results/"

try
    for (key, value) in output
        filename_main = joinpath(results_path, "$key.csv")
        filename_alt = joinpath(results_alt_path, "$key.csv")
        CSV.write(filename_main, value)
        CSV.write(filename_alt, value)
    end
catch e
    println("❌ Σφάλμα κατά την αποθήκευση κάποιων .csv αρχείων: $e")
end

include("flow_calculator.jl")
calculate_and_save_flows(PTDF_df, Lines, eno_model, results_path; verbose=true)
calculate_and_save_flows(PTDF_df, Lines, eno_model, results_alt_path; verbose=false)

include("Plots.jl")

energy_price = CSV.read(joinpath(PATH_global, "results/energy_price.csv"), DataFrame)
line_flows = CSV.read(joinpath(PATH_global, "results/line_flows.csv"), DataFrame)
plot_nodal_maps(eno_model, line_flows, energy_price, Ref_hub)  # default
plot_nodal_maps(eno_model, line_flows, energy_price, Ref_hub, results_alt_path)  # νέα αποθήκευση

# Copy viewer.html στον νέο φάκελο (αν υπάρχει το αρχείο στην τρέχουσα διαδρομή)
viewer_src = joinpath(PATH_global, "results", "viewer.html")
viewer_dst = joinpath(results_alt_path, "viewer.html")
if isfile(viewer_src)
    cp(viewer_src, viewer_dst; force=true)
else
    println("⚠️ Δεν βρέθηκε το viewer.html στο $viewer_src")
end

plot_energy_price(joinpath(PATH_global, "results/energy_price.csv"))
plot_energy_price(joinpath(PATH_global, "results/energy_price.csv"), results_alt_path)

end 

############################################
#### Τελικός χρόνος
############################################
  

println("--- SCRIPT FINISHED ---")
total_time = time_info.time
memory_allocated_MB = time_info.bytes / (1024^2)

log_run_metrics(eno_model, day_type, target_countries, model_solve_time, total_time, memory_allocated_MB)  
println("✅ Το μοντέλο εκτελέστηκε και αποθηκεύτηκε επιτυχώς:")
println(" → CSV και flows: $results_path & $results_alt_path")
println(" → Plots: $results_path/nodal_maps_t & $results_alt_path/nodal_maps_t")
println("Model solve time: $(round(model_solve_time, digits=3)) seconds")
println("Total execution time: $(round(total_time, digits=3)) seconds")
println("Συνολική RAM δεσμευμένη από Julia: $(round(memory_allocated_MB, digits=2)) MB")
