function define_solver(solver_name, gurobi_env)
   # create model using solver: solver_name
   if solver_name == "Gurobi"
      Solver = optimizer_with_attributes(() -> Gurobi.Optimizer(gurobi_env), "OutputFlag" => 0, "MIPGap" => 1e-3)
      model = Model(Solver)
   elseif solver_name == "Xpress"
      model = Model(Xpress.Optimizer)
   end
    
   return model
end

function get_lp_model(model::Model)
    # Διατρέχουμε όλες τις μεταβλητές του μοντέλου
    for v in all_variables(model)
        
        if is_binary(v)
            unset_binary(v)
        elseif is_integer(v)
            unset_integer(v)
        end
    end

    return model
end

function fix_model(model::Model, model_lp::Model)
   # Fix the binary variables of the lp relaxation
   w = model[:w]
   for id in eachindex(w)
      variable = model_lp[:w][id]
      val = value(w[id]) 
      fix(variable, val; force = true)
   end
end

function unfix_model(model_lp::Model)
   # Unfix the binary variables of the lp relaxation
   w = model_lp[:w] 
   for id in eachindex(w)
      variable = model_lp[:w][id]
      if is_fixed(variable)
         unfix(variable)
      end
   end
end

function get_da_prices(model::Model)
   DA_prices = Dict()

   for zone in zones.Bus 
      # NOTE: The resolution is 15min so the prices are EUR/MW15min, to convert to EUR/MWh we multiply by 4
      DA_prices[zone] = convert(Array,dual.(model[:load_balance_constraint])[zone, :])*4 
   end

   return DA_prices
end 

function get_all_solution(model::Model)
   x = union(all_variables(model), all_parameters(model))
   output = DataFrame(
   name = name.(x),
   Value = value.(x),
   )
   return output
end

function get_outputs(model::Model, model_lp)
   output = Dict()
   output["total_cost"] = objective_value(model)
   if !isnothing(model_lp)
      output["energy_price"] = get_da_prices(model_lp)
   end
   output["zonal_total_cost"] = Dict()
   output["minload_cost"] = Dict()
   output["startup_cost"] = Dict()
   output["production_cost"] = Dict()
   output["shedding_cost"] = Dict()
   output["technology_cost"] = Dict()
   output["commitment"] = Dict()
   output["net_positions"] = Dict()

   for zone in zones.Bus
      # objective function 
      output["zonal_total_cost"][zone] =  value(model[:zonal_total_cost][zone])
      
      output["minload_cost"][zone] = value(model[:minload_cost][zone])
      output["startup_cost"][zone] = value(model[:startup_cost][zone])
      output["production_cost"][zone] = value(model[:production_cost][zone])
      output["shedding_cost"][zone] = value(model[:shedding_cost][zone])

      output["technology_cost"][zone] = Dict()
      for fuel in unique(generators.FuelGenerator) 
         output["technology_cost"][zone][fuel] = value(model[:technology_cost][zone, fuel])    
      end
    
    end
    
   for g in generators_id["conventional"]
       if generators.GeneratorType[g] == "SLOW"
           for t in :1:T_hour
               output["commitment"]["w[$g,$t]"] = value(model[:w][g, t])           
           end
       end
   end 

   for zone in PTDF_zones
      for t in 1:T_15
         output["net_positions"]["r[$zone,$t]"] = value(model[:r][zone, t])   
      end
   end
   return output
end

using DataFrames

function get_outputs_df(model::Model, model_lp)
    output = Dict()

    # Total cost
    output["total_cost"] = DataFrame(total_cost = [objective_value(model)])

       
    # Initialize DataFrames for each category
    zonal_total_cost = DataFrame(zone = String[], total_cost = Float64[])
    minload_cost = DataFrame(zone = String[], cost = Float64[])
    startup_cost = DataFrame(zone = String[], cost = Float64[])
    production_cost = DataFrame(zone = String[], cost = Float64[])
    shedding_cost = DataFrame(zone = String[], cost = Float64[])
    technology_cost = DataFrame(zone = String[], fuel = String[], cost = Float64[])
    commitment = DataFrame(generator = String[], time = Int[], value = Float64[])
    net_positions = DataFrame(zone = String[], time = Int[], value = Float64[])
    energy_price = DataFrame(zone = String[], time = Int[], value = Float64[])
    power_generation = DataFrame(zone = String[], bus = String[],fuel = String[], generator = String[], time = Int[], value = Float64[])
    power_generation_total = DataFrame(country = String[], bus = String[], fuel = String[], total_value = Float64[])
    power_balance = DataFrame(zone = String[], time = Int[], fuel_generation = Float64[], renewable_generation = Float64[], load_shedding = Float64[], production_shedding = Float64[], net_positions = Float64[], load_bus = Float64[])

    # Populate the zonal costs and technology costs
    for zone in zones.Bus
        push!(zonal_total_cost, (zone, value(model[:zonal_total_cost][zone])))
        push!(minload_cost, (zone, value(model[:minload_cost][zone])))
        push!(startup_cost, (zone, value(model[:startup_cost][zone])))
        push!(production_cost, (zone, value(model[:production_cost][zone])))
        push!(shedding_cost, (zone, value(model[:shedding_cost][zone])))

        for fuel in unique(generators.FuelGenerator)
            push!(technology_cost, (zone, fuel, value(model[:technology_cost][zone, fuel])))
        end
    end

    # Populate commitment data
    for g in generators_id["conventional"]
        if generators.GeneratorType[g] == "Slow"
            for t in 1:T_hour
                push!(commitment, (generators.Generator[g], t, value(model[:w][g, t])))
            end
        end
    end 

    # Populate net positions
    for zone in zones.Bus
        for t in 1:T_15
            push!(net_positions, (zone, t, value(model[:r][zone, t])))
        end
    end

        # Populate energy_prices
        energy_price_dict = get_da_prices(model_lp)
    for zone in zones.Bus
        for t in 1:T_15 
            push!(energy_price, (zone, t, energy_price_dict[zone][t]))
        end
    end

    #Populate power_generation
    for g in generators_id["conventional"]
        bus = generators.BusGenerator[g] 
        fuel = generators.FuelGenerator[g]  
        generator_name = generators.Generator[g]  
        
        country = replace(generators.FHGenerator[g], "FH_" => "")

        for t in 1:T_15
            push!(power_generation, (country, bus, fuel, generator_name, t, value(model[:p][g, t])))
        end
    end


    #Populate power_generation_total 

    total_generation = Dict{Tuple{String, String, String}, Float64}() 

    for g in generators_id["conventional"]
        bus = generators.BusGenerator[g]  # Κόμβος (Node)
        fuel = generators.FuelGenerator[g]  # Καύσιμο

        # Βρίσκουμε τη χώρα από το FHGenerator, αφαιρώντας το "FH_"
        country = replace(generators.FHGenerator[g], "FH_" => "")

        # Υπολογισμός της συνολικής παραγωγής
        total_production = 0.0
        for t in 1:T_15
            total_production += value(model[:p][g, t])
        end

        # Ενημέρωση του λεξικού με τη συνολική παραγωγή
        key = (country, bus, fuel)    
        total_generation[key] = get(total_generation, key, 0.0) + total_production 
    end

    # Προσθήκη στο power_generation_total
    for ((country, bus, fuel), total_value) in total_generation
        push!(power_generation_total, (country, bus, fuel, total_value)) 
    end


    ##### Populate power_balance 

    for zone in zones.Bus
        for time in 1:T_hour

        # Υπολογισμός παραγωγής ανά τύπο καυσίμου
            fuel_generation = 0.0
            for g in generators_id_per_zone["conventional"][zone]
                    for t in ((time - 1) * 4 + 1):(time * 4)
                 fuel_generation += sum(value(model[:p][g, t])) * (1/4)
                    end
            end 

           # Υπολογισμός παραγωγής από ανανεώσιμες πηγές
           renewable_generation = 0.0 
           for g in generators_id_per_zone["renewable"][zone]
                    for t in ((time - 1) * 4 + 1):(time * 4) 
                        renewable_generation += sum(value(model[:p_re][g, t])) * (1/4)
                    end
            end

        # Υπολογισμός load shedding
            load_shedding = 0.0
            for t in ((time - 1) * 4 + 1):(time * 4)
                load_shedding += sum(value.(model[:ls][zone, t])) * (1/4)
            end

        # Υπολογισμός production shedding
            production_shedding = 0.0
            for t in ((time - 1) * 4 + 1):(time * 4)
                production_shedding += sum(value.(model[:ps][zone, t])) * (1/4)
            end

        # Υπολογισμός net positions
            net_positions = 0.0
            for t in ((time - 1) * 4 + 1):(time * 4)
                net_positions += sum(value(model[:r][zone, t])) * (1/4)
            end

        # Ανάγνωση φορτίου για τη ζώνη
        load_zone = model[:load_zone]
        load_bus = sum(value(load_zone[zone, t]) for t in ((time - 1) * 4 + 1) : (time * 4)) * (1/4)


            push!(power_balance, (zone, time, fuel_generation, renewable_generation, load_shedding, production_shedding, net_positions, load_bus))
        end 
    end
        # Assign the DataFrames to the output dictionary
        output["zonal_total_cost"] = zonal_total_cost
        output["minload_cost"] = minload_cost
        output["startup_cost"] = startup_cost
        output["production_cost"] = production_cost
        output["shedding_cost"] = shedding_cost
        output["technology_cost"] = technology_cost
        output["commitment"] = commitment
        output["net_positions"] = net_positions
        output["energy_price"] = energy_price
        output["power_generation"] = power_generation
        output["power_generation_total"] = power_generation_total
        output["power_balance"] = power_balance

        # Εξασφαλίζω ότι όλες οι τιμές στο output είναι DataFrame
        for key in keys(output)
            if !(output[key] isa DataFrame)
                output[key] = DataFrame(value = [output[key]])
            end
        end

        return output 
    end



