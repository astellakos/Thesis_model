using JuMP

function attach_energy_only_clearing_model!(model::Model, day_type::String)
    ############## variables 

    # unit comitmment variables
    @variable(model, w[generators_id["conventional"], 1:T_hour], Bin) 

    # start-up variables
    @variable(model, z[generators_id["conventional"], 1:T_hour] >= 0) 

    # production variables 
    @variable(model, p[generators_id["conventional"], 1:T_15] >= 0)  

    # load shedding variables 
    @variable(model, ls[zones.Bus, 1:T_15] >= 0)  

    # prod shedding variables 
    @variable(model, ps[zones.Bus, 1:T_15] >= 0)  

    # Nodal net injection 
    @variable(model, r[zones.Bus, 1:T_15])  

    ############## parameters 
    #load_parametrization
    @variable(model, load_zone[zones.Bus, 1:T_15] == 0.0, Param())

    # renewable generators parametrization 
    @variable(model, p_re[generators_id["renewable"], 1:T_15] == 0.0, Param()) 

    ############## constraints 

    # load balance
    
    @constraint(model, load_balance_constraint[zone in zones.Bus, t in 1:T_15], 
        (sum(p[g, t] for g in generators_id_per_zone["conventional"][zone]) 
        + sum(p_re[g, t] for g in generators_id_per_zone["renewable"][zone]) 
        + ls[zone, t] 
        - ps[zone, t]
        - r[zone, t]
        == load_zone[zone, t])
    )

    # Sum of net injection == 0

    @constraint(model, net_sum_zero[t in 1:T_15],
    sum(r[zone,t] for zone in zones.Bus) == 0.0
    ) 
    
    # max power
    max_power_constraint = Dict{Tuple{Int, Int}, ConstraintRef}() # Container of max_power_constraint constraints 

    for g in generators_id["conventional"] 
        for t in :1:T_15
            max_power_constraint[g, t] = @constraint(model, p[g, t]  <= generators.MaxRunCapacity[g]*w[g, map_t[t]]) #*get_planned_outage(g,day_type)
        end
    end

    # min power
    @constraint(model, min_power_constraint[g in generators_id["conventional"], t in 1:T_15], p[g, t] >= generators.MinRunCapacity[g]*w[g, map_t[t]]) 
    
    # ramp constraints
    ramp_up_constraint = Dict{Tuple{Int, Int}, ConstraintRef}() # Container of ramp-up constraints 
    ramp_down_constraint = Dict{Tuple{Int, Int}, ConstraintRef}() # Container of ramp-down constraints 
    
    for t in 1:T_15
        for g in generators_id["conventional"]
            # wrap-up generator over the horizon
            t_m = t-1 
            if t_m < 1 
                t_m = T_15
            end

            # ramp-up 
            ramp_up_constraint[(g, t)] = @constraint(model, p[g, t] - p[g, t_m] <= round(15*generators.RampUp[g], digits=1))

            # ramp-down 
            ramp_down_constraint[(g, t)] = @constraint(model, p[g, t_m] - p[g, t] <= round(15*generators.RampUp[g], digits=1))        
        end
    end
    
    # minimum times
    for g in generators_id["conventional"]
        for t in 1:T_hour
            
            # wrap-up generator up-time over the horizon
            ut_start = t-generators.UT[g]+1

            if ut_start < 1
                ut_set = [t]
                period = t
                counter = 0 
                while counter < generators.UT[g] && counter < T_hour-1
                    period += -1
                    if period == 0
                        period = T_hour
                    end
                    push!(ut_set, period)
                    counter += 1
                end
            else
                ut_set = t-generators.UT[g]+1:t
            end

            # minimum up times
            @constraint(model, sum(z[g, q] for q in ut_set) <= w[g, t])

            # wrap-up generator down-time over the horizon
            dt_set = []
            period = t
            counter = 0 
            while counter < generators.DT[g] && counter < T_hour
                period += 1
                if period > T_hour
                    break
                end
                push!(dt_set, period)
                counter += 1
            end
 
            # minimum down times
            @constraint(model, sum(z[g, q] for q in dt_set) <= 1 - w[g, t])
        end
    end
    
    # relaxation of integrality of z 
    @constraint(model, [g in generators_id["conventional"], t in 1:T_hour], z[g, t] <= 1)

    # transition of start up variables 
    @constraint(model, [g in generators_id["conventional"]], z[g, 1] >= w[g, 1])
    @constraint(model, [g in generators_id["conventional"], t in 2:T_hour], z[g, t] >= w[g, t] - w[g, t-1])
    
    # objective function 
    @objective(model, Min, sum(w[g, t]*generators.NoLoadConsumption[g]*generators.FuelPrice[g]  # no load cost of generators 
    + z[g, t]*generators.StartupCost[g] for g in generators_id["conventional"], t in 1:T_hour)  # start up cost of generator                                                            
    + (1/4)*sum( (generators.mean_cost[g] + generators.mean_CO2_cost[g]) * p[g, t] for g in generators_id["conventional"], t in 1:T_15)  # production cost of generators
    + (1/4)*sum(ls)*VOLL  # load shedding 
    ) 

    # expressions 
    add_cost_expressions!(model)
end

function attach_PTDF_model!(model::Model, PTDF_data::Dict)
    r = model[:r] 

    for (i, line) in enumerate(Lines.Line)
        for t in 1:T_15
            @constraint(model,sum(r[n, t] * PTDF_data[line][n][1][] for n in zones.Bus) <= Lines.FlowLimitForw[i]  )
           end
    end
    for (i, line) in enumerate(Lines.Line)
        for t in 1:T_15
            @constraint(model,sum(r[n, t] * PTDF_data[line][n][1][] for n in zones.Bus) >= -Lines.FlowLimitBack[i] )
           end
    end

    #=for cne in eachindex(PTDF_data[day_type].cneName) 

        #if !occursin("External", PTDF_data[day_type].cneName[cne])
            t_hour = get_associated_t(cne, day_type) 
            for t in inv_map_t[t_hour] 
                @constraint(model, sum(r[n, t]*PTDF_data[day_type][cne, "ptdf_"*n] for n in PTDF_zones) <= PTDF_data[day_type][cne, "ram"])
            end
        #end 
    end 
    
    # Set net position for not modeled zones  
    for zone in setdiff(PTDF_zones, zones)   
        for t in 1:T_15   
            fix(r[zone, t], 0; force=true)
        end  
    end =#

end 

function set_up_loads!(model::Model, day_type::String)

    load_zone = model[:load_zone]

    # set up load 
    for zone in zones.Bus
        temp_load = zeros(T_15)

        # check buses associated to the zone 
        idx = findall(zone .== buses.Bus)

        # check if there is a load associated to the bus
        for id in idx 
            bus = buses.Bus[id]
            load_id = findall(bus .== loads.BusLoad)

            if !isempty(load_id)
                profile = loads.DynamicProfileLoad[load_id[1]]

                # check it's not stochastic
                profile_id = findall(profile .== dynamic_profiles.DynamicProfile)[1]
                profile_type = dynamic_profiles.ProfileType[profile_id]

                if profile_type != "deterministic"
                    error("stochastic loads are not supported")
                end

                # get reference value 
                reference_value = loads.ReferenceValueLoad[load_id]

                # get rates
                idx_profiles = findall(profile .== determ_profile_rates.DynamicProfile)
                id_rate = findall(day_type .== determ_profile_rates.DayType[idx_profiles])[1]

                rates = reference_value .* values(determ_profile_rates[idx_profiles[id_rate], 3:end])
                temp_load .+= rates
            else
            end
        end

        for t in 1:T_15
            set_value(load_zone[zone, t], temp_load[t])
        end
    end

end


function set_up_renewables!(model::Model, day_type::String, sample, first_load=true)
    p_re = model[:p_re]

    # set up renewables 
    for zone in zones.Bus 
        
        # loop for renewable generators associated to the zone
        for g in generators_id_per_zone["renewable"][zone] 
            bus = generators_RE.BusGeneratorRE[g]
            profile = generators_RE.DynamicProfileRE[g]

            # get reference value 
            reference_value = generators_RE.ReferenceValueRE[g]

            # check it's stochastic
            profile_id = findall(profile.== dynamic_profiles.DynamicProfile)[1]
            profile_type = dynamic_profiles.ProfileType[profile_id]

            if profile_type == "deterministic" && first_load
                # get rates
                idx_profiles = findall(profile.== determ_profile_rates.DynamicProfile)
                id_rate = findall(day_type.== determ_profile_rates.DayType[idx_profiles])[1]

                rates = reference_value.*values(determ_profile_rates[idx_profiles[id_rate], 3:end])
              
                for t in 1:T_15
                    set_value(p_re[g, t], rates[t])
                end
            elseif profile_type == "stochastic"
                # get rates
                idx_profiles = findall(profile.== stoch_profile_rates.DynamicProfile)
                idx_samples = findall(day_type.== stoch_profile_rates.DayType[idx_profiles])
                if typeof(sample) ==  Int64
                    rates = reference_value.*values(stoch_profile_rates[idx_profiles[idx_samples[sample]], 5:end])
                elseif sample == "average"
                    data = Matrix(stoch_profile_rates[idx_profiles[idx_samples], 5:end])
                    rates = reference_value.*mean(data, dims=1)
                end
                
                for t in 1:T_15
                    set_value(p_re[g, t], rates[t])        
                end
            end
        end

        
    end
end


#= function run_eno_day_type(eno_model::Model, eno_lp_model::Model, day_type)
    sample = "average"
    #########################
    #### unfix values (if fixed) 
    unfix_model(eno_lp_model)

    # set up loads profiles
    set_up_loads!(eno_model, day_type)
    set_up_loads!(eno_lp_model, day_type)

    # set up renewable profile 
    set_up_renewables!(eno_model,  day_type, sample)
    set_up_renewables!(eno_lp_model,  day_type, sample)

    # set up planned outage 
    #set_up_planned_outages!(eno_model, day_type)
    #set_up_planned_outages!(eno_lp_model, day_type)

    # optimize the model
    optimize!(eno_model)
    termination_status(eno_model)
    objective_value(eno_model)

    # fix binary values for lp model
    fix_model(eno_model, eno_lp_model)

    # optimize lp model
    optimize!(eno_lp_model)
end =#

function add_cost_expressions!(model::Model)
    w = model[:w]
    z = model[:z]
    p = model[:p]
    ls = model[:ls]
    
    # Breakdown of costs
    # zonal cost
    @expression(model, zonal_total_cost[zone in zones.Bus], sum(w[g, t]*generators.NoLoadConsumption[g]*generators.FuelPrice[g]  
    + z[g, t]*generators.StartupCost[g] for g in generators_id_per_zone["conventional"][zone], t in 1:T_hour)                                           # start up cost of generators
    + (1/4)*sum( (generators.mean_cost[g] + generators.mean_CO2_cost[g]) * p[g, t] for g in generators_id_per_zone["conventional"][zone], t in 1:T_15)  # production cost of generators
    + (1/4)*sum(ls[zone,t] for  t in 1:T_15)*VOLL  # load shedding
    ) 

# No load cost of generators 
@expression(model, minload_cost[zone in zones.Bus], sum(w[g, t]*generators.NoLoadConsumption[g]*generators.FuelPrice[g] 
for g in generators_id_per_zone["conventional"][zone], t in 1:T_hour))

# start up cost of generator 
@expression(model, startup_cost[zone in zones.Bus], sum(z[g, t]*generators.StartupCost[g] for g in generators_id_per_zone["conventional"][zone] , t in 1:T_hour))

# production cost of generators
@expression(model, production_cost[zone in zones.Bus], (1/4)*sum( (generators.mean_cost[g] + generators.mean_CO2_cost[g]) * p[g, t] for g in generators_id_per_zone["conventional"][zone], t in 1:T_15))   

# load shedding
@expression(model, shedding_cost[zone in zones.Bus], (1/4)*sum(ls[zone,t] for t in 1:T_15)*VOLL)      

# Get fuels
    fuel_types = unique(generators.FuelGenerator)
    fuel_generators = Dict()

    for zone in zones.Bus 
        fuel_generators[zone] = Dict()
        for fuel in fuel_types
            fuel_generators[zone][fuel] = []
        end
        
        for g in generators_id_per_zone["conventional"][zone]
            fuel = generators.FuelGenerator[g]
            push!(fuel_generators[zone][fuel], g)
        end
    end


    @expression(model, technology_cost[zone in zones.Bus, fuel in fuel_types], sum(w[g, t]*generators.NoLoadConsumption[g]*generators.FuelPrice[g]  
    + z[g, t]*generators.StartupCost[g] for g in fuel_generators[zone][fuel], t in 1:T_hour)                                           # start up cost of generators
    + (1/4)*sum( (generators.mean_cost[g] + generators.mean_CO2_cost[g]) * p[g, t] for g in fuel_generators[zone][fuel], t in 1:T_15))  # production cost of generators 
end 
