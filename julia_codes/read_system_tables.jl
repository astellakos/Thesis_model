
function read_system_tables(systemdir::AbstractString; DisplayWarnings::Bool=true)
	
	# read static technical data using standard CSV.read function
	Float64m = Union{Float64, Missings.Missing}
	Boolm = Union{Bool, Missings.Missing} 

	Generators = CSV.read(string(systemdir, "/Generators.csv"), DataFrame,
		types=[String, String, String, Float64m, Float64, Float64, Float64,
		Float64m, Float64m, Float64m, Float64, Boolm, Float64m, Float64m,
		Float64, String, String, String, Float64])
	HeatRateCurves = CSV.read(string(systemdir, "/HeatRateCurves.csv"), DataFrame,
		types=[String, String, Float64, Float64])
	FuelPrice = CSV.read(string(systemdir, "/FuelPrice.csv"), DataFrame,
		types=[String, String, Float64])
	GeneratorsRE = CSV.read(string(systemdir, "/GeneratorsRE.csv"), DataFrame,
		types=[String, String, String, Float64, String])
	Loads = CSV.read(string(systemdir, "/Loads.csv"), DataFrame,
		types=[String, String, String, Float64, Float64])
	DynamicProfiles = CSV.read(string(systemdir, "/DynamicProfiles.csv"), DataFrame,
		types=[String, String])
	Buses = CSV.read(string(systemdir, "/Buses.csv"), DataFrame, types=[String, String, Float64m, Float64m, String])
	Lines = CSV.read(string(systemdir, "/Lines.csv"), DataFrame,
		types=[String, String, String, String, Float64m, Float64, Float64, Float64])

			#Reserves = CSV.read(string(systemdir, "/Reserves.csv"), DataFrame,
	#	types=[String, String, String, Float64, Float64, String, Float64, Float64])
	
	# check that static data makes sense
	if any(indexin(unique(Lines.LineType), ["AC", "DC"]) .== 0)
		error("unrecognized line type. Supported types are AC and DC.")
	end
	
	# read planned outage data using standard CSV.read function
	GeneratorPlannedOutages = CSV.read(string(systemdir, "/GeneratorPlannedOutages.csv"), DataFrame,
		types=[String, String, String, Int, Int, Float64])
	#LinePlannedOutages = CSV.read(string(systemdir, "/LinePlannedOutages.csv"), DataFrame,
	#	types=[String, String, Int, String, Int, Int])
	# read dynamic profiles using specialized reader
	DetermProfileRates = CSV.read(string(systemdir,
		"/DeterministicProfileRates.csv"), DataFrame)
	StochProfileRates = CSV.read(string(systemdir,
		"/StochasticProfileRates.csv"), DataFrame)
    
    # replace missings to 0
	Generators = coalesce.(Generators, 0)
	GeneratorPlannedOutages = coalesce.(GeneratorPlannedOutages, 0)
	GeneratorsRE = coalesce.(GeneratorsRE, 0)
	Loads = coalesce.(Loads, 0)
	DynamicProfiles = coalesce.(DynamicProfiles, 0)
	DetermProfileRates = coalesce.(DetermProfileRates, 0)
	StochProfileRates = coalesce.(StochProfileRates, 0)
	Buses = coalesce.(Buses, 0)
	#Lines = coalesce.(Lines, 0)
	#LinePlannedOutages = coalesce.(LinePlannedOutages, 0)
	#Reserves = coalesce.(Reserves, 0)
	HeatRateCurves = coalesce.(HeatRateCurves, 0)
	FuelPrice = coalesce.(FuelPrice, 0)

	# add fuel costs to generators
	Generators = add_fuels_cost(Generators, FuelPrice)

	# add mean costs to generators
	Generators = get_mean_cost(Generators, HeatRateCurves)

	# convert UT, DT to Int64
	Generators.UT = convert.(Int64, Generators.UT)
	Generators.DT = convert.(Int64, Generators.DT)

	# return all read data frames
	return Generators, GeneratorPlannedOutages, GeneratorsRE, Loads,
		DynamicProfiles, DetermProfileRates, StochProfileRates,
		Buses, #Reserves, 
		HeatRateCurves, FuelPrice, Lines
end 

function get_generators_id(generators, generators_RE, buses::DataFrame, zones::DataFrame)

    generators_id_per_zone = Dict("conventional" => Dict{Any, Vector{Int}}(), "renewable" => Dict{Any, Vector{Int}}())
    generators_id = Dict("conventional" => Int[], "renewable" => Int[])

    # conventional
    for zone in zones.Bus
        generators_id_per_zone["conventional"][zone] = Int[]
    end

    for l in eachindex(generators.Generator)
        idxs = findall(generators.BusGenerator[l] .== buses.Bus)
        if !isempty(idxs)
            idx = idxs[1]
            zone = buses.Bus[idx]  # Χρησιμοποιούμε τον ίδιο τον κόμβο ως "ζώνη"
            if zone in zones.Bus
                push!(generators_id_per_zone["conventional"][zone], l)
                push!(generators_id["conventional"], l)
            end
        end
    end

    # renewables
    for zone in zones.Bus
        generators_id_per_zone["renewable"][zone] = Int[]
    end

    for l in eachindex(generators_RE.GeneratorRE)
        idxs = findall(generators_RE.BusGeneratorRE[l] .== buses.Bus)
        if !isempty(idxs)
            idx = idxs[1]
            zone = buses.Bus[idx]
            if zone in zones.Bus
                push!(generators_id_per_zone["renewable"][zone], l)
                push!(generators_id["renewable"], l)
            end
        end
    end

    return generators_id_per_zone, generators_id
end

using Random

function add_fuels_cost(generators, fuel_price)
	Random.seed!(1234) 

	generators.FuelPrice = zeros(length(generators.Generator))

	for l in eachindex(generators.Generator)
		fuel = generators.FuelGenerator[l] 
		fuel_hub = generators.FHGenerator[l]
		idx_fh = findall(fuel_hub .== fuel_price.FuelHub)
        idx_f = findall(fuel .== fuel_price.Fuel)
        
		id_sets = intersect(idx_f,idx_fh)

		if isempty(id_sets)
			pos = idx_f[1]
			
		else
			pos = id_sets[1]
		end

		random_const = rand() - 0.5
		generators.FuelPrice[l] = fuel_price.Price[pos] * (1 + random_const)
	end

	return generators
end

function create_min_map(T_15)
	# map t in 15 min interval to t_hourly
    map_t = Dict() 
	
	t_hour = 1
	t_count = 0
	for t in 1:T_15
		if t_count < 4
			t_count += 1
		else
			t_count = 1
			t_hour += 1
		end
		map_t[t] = t_hour
	end

	inv_map_t = Dict()

	t_count = 0 
    for t in 1:T_hour
		inv_map_t[t] = []
		for i in 1:4
			t_count += 1
			push!(inv_map_t[t], t_count)
		end
	end
    #println(inv_map_t)
	return map_t, inv_map_t
end

function get_mean_cost(generators, heat_rate_curves)
	generators.mean_cost = zeros(length(generators.Generator))
	generators.mean_CO2_cost = zeros(length(generators.Generator))

	for g in eachindex(generators.Generator)
        
		# get mean heat rate
		min_p = generators.MinRunCapacity[g]
		max_p = generators.MaxRunCapacity[g]

		HRS = generators.HRSGenerator[g]
		idx = findall(HRS .== heat_rate_curves.SeriesHRC)
		heat = []
		for p in min_p:1:max_p 
			heat_array = []
			for id in idx
				push!(heat_array, (heat_rate_curves.InterceptHRC[id] + heat_rate_curves.SlopeHRC[id]*p) )  
			end
			push!(heat, maximum(heat_array))
		end

        mean_val = mean(heat)
        idx_c = findall(mean_val .>= heat)[end]
        mean_heat = mean_val/collect(min_p:1:max_p)[idx_c]

		# get costs
		# COST fuels: heat rate GJ/MWh, fuel price EUR/GJ, power MWh,-> EUR
		generators.mean_cost[g] = mean_heat*generators.FuelPrice[g]

		# COST emissions: heat rate GJ/MWh,CO2 rate TON/GJ, price EUR/TON , power MWh -> EUR
		generators.mean_CO2_cost[g] = mean_heat*generators.CO2Rate[g]*CO2PRICE
        #=
		# Negative rates are considered to provide a 0 cost 
		if generators.CO2Rate[g] < 0 
			generators.mean_CO2_cost[g] = 0
        else
			generators.mean_CO2_cost[g] = mean_heat*generators.CO2Rate[g]*CO2PRICE
		end
        =#
		#=
		ramp_up = generators.RampUp[g]

		possibles_p = [min_p]
        curr_p = min_p
		while true 
			curr_p += ramp_up
			if curr_p > max_p
				break
			else
			    push!(possibles_p, curr_p)
			end
		end	
        =#
	end

	return generators	
end

#= function read_day_ahead_prices(systemdir, year_, zone)
	#println("loading data DA prices: $zone $year_")
	if zone == "DE/LX"
		xf = XLSX.readxlsx(systemdir*"DE_DA_prices_$year_.xlsx")
        prices = xf["Sheet1"]["B"]
	else 
		xf = XLSX.readxlsx(systemdir*zone*"_DA_prices_$year_.xlsx")
        prices = xf["Sheet1"]["B"]
    end
    
    
    if Dates.isleapyear(year_)
        day = Date(year_, 2, 29)
        leap_day = Dates.dayofyear(day)
    else
        leap_day = 0 
    end

    day_ahead_prices = Dict()
    day_ahead_prices[zone] = zeros(24, 365)

    pos_s = 7
    for day = 1:365
        if ismissing(prices[pos_s+2]) 
            #println(pos_s)
            # Day with 23 hours due the summer change of hour
            day_ahead_prices[zone][1:2, day] = parse.(Float64, prices[pos_s:pos_s+1])
            day_ahead_prices[zone][3, day] = parse.(Float64, prices[pos_s+3])
            day_ahead_prices[zone][4:end, day] = parse.(Float64, prices[pos_s+3:pos_s+23])
            pos_s += 23 + 4
        elseif pos_s+24 > length(prices) || ismissing(prices[pos_s+24])
            # Typical day with 24 hours
            day_ahead_prices[zone][:, day] = parse.(Float64, prices[pos_s:pos_s+23])
            pos_s += 23 + 4
        else 
            #println(pos_s)
            # Day with 25 hours due the winter change of hour
            day_ahead_prices[zone][:, day] = parse.(Float64, prices[pos_s:pos_s+23])
            pos_s += 24 + 4
        end
    end

    return day_ahead_prices
end =#

#= function array_types(year_::Int64)
    
    ARRAY = Dict()
	# spring array 
	ARRAY["Spring"] = collect(Date(year_,3,1):Day(1):Date(year_,5,31))#collect(Date(year_,3,20):Day(1):Date(year_,6,20))#

	# summer array 
	ARRAY["Summer"] = collect(Date(year_,6,1):Day(1):Date(year_,8,31))#collect(Date(year_,6,21):Day(1):Date(year_,9,22))#

	# autumn array 
	ARRAY["Autumn"] = collect(Date(year_,9,1):Day(1):Date(year_,11,30))#collect(Date(year_,9,23):Day(1):Date(year_,12,21))#

	# winter array 
	#ARRAY["Winter"] = union(collect(Date(year_,1,1):Day(1):Date(year_,3,19)), collect(Date(year_,12,22):Day(1):Date(year_,12,31)))
	
	if Dates.isleapyear(year_) 
		ARRAY["Winter"] = union(collect(Date(year_,1,1):Day(1):Date(year_,2,29)), collect(Date(year_,12,1):Day(1):Date(year_,12,31)))
    else
		ARRAY["Winter"] = union(collect(Date(year_,1,1):Day(1):Date(year_,2,28)), collect(Date(year_,12,1):Day(1):Date(year_,12,31)))
	end
    
	DAY_TYPES_ARRAY = Dict()
	for day_type in DAY_TYPES
		DAY_TYPES_ARRAY[day_type] = []
    end

    for season in ["Spring", "Summer", "Autumn", "Winter"]    
		for day in ARRAY[season]
			day_ = Dates.dayofyear(day)
			if Dates.dayofweek(day) in [6,7]
				type = "WE"
            else
				type = "WD"
			end	
			day_type = 	season*type
			push!(DAY_TYPES_ARRAY[day_type], day_)
        end
	end

	if Dates.isleapyear(year_)
        for day_type in keys(DAY_TYPES_ARRAY)
			if 366 in DAY_TYPES_ARRAY[day_type] 
				deleteat!(DAY_TYPES_ARRAY[day_type], findall(x->x==366,DAY_TYPES_ARRAY[day_type]))

			end
		end
    end

    return DAY_TYPES_ARRAY
end =#

#= function final_day_ahead_prices(systemdir, years)
    zones_temp = zones#["BE"]
	in_year = years[1]
	DAY_TYPES_ARRAY = array_types(in_year)
	day_ahead_prices = Dict()

	for zone in zones_temp 
		day_ahead_prices[zone] = read_day_ahead_prices(systemdir, in_year, zone)[zone] 
    end   

	if length(years) > 1

		n_rep = Dict()
		for zone in zones_temp
			n_rep[zone] = Dict()
			for day in 1:365
				n_rep[zone][day] = 1
            end
		end

		for year_ in years[2:end] 
			DAY_TYPES_ARRAY_ = array_types(year_)  
			day_ahead_prices_ = Dict()
			for zone in zones_temp 
				day_ahead_prices_[zone] = read_day_ahead_prices(systemdir, year_, zone)[zone] 
			end
			#day_ahead_prices_ = read_day_ahead_prices(systemdir, year_, zone)

			for zone in zones_temp
				for day_type in DAY_TYPES
					days_ = DAY_TYPES_ARRAY_[day_type]
					days = DAY_TYPES_ARRAY[day_type]
                    
					i = 0
					while i < length(days) && i < length(days_)
						i += 1
                        day_ = days_[i]
						day = days[i]
						day_ahead_prices[zone][:, day] .+= day_ahead_prices_[zone][:, day_]
						n_rep[zone][day] += 1
                    end
                end
			end
		end

		for zone in zones_temp
			for day_type in DAY_TYPES 
				for day in DAY_TYPES_ARRAY[day_type]
					day_ahead_prices[zone][:, day] = day_ahead_prices[zone][:, day]./n_rep[zone][day]
				end
			end
		end

	end

	return day_ahead_prices, DAY_TYPES_ARRAY
end =#

function load_ptdf_data(systemdir, Ref_hub)

	file_path = joinpath(systemdir, "/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/results/ptdf_calc/PTDF_matrix_theoretical.csv")
    PTDF_df = CSV.read(file_path, DataFrame)

	PTDF_df[!, Symbol(Ref_hub.Bus)] = zeros(nrow(PTDF_df))
	
    PTDF_data = Dict()
    for line in Lines.Line
        PTDF_data[line] = Dict()
		for n in zones.Bus
            PTDF_data[line][n] = PTDF_df[isequal.(PTDF_df.Line, line), n]
        end
    end
    return PTDF_data, PTDF_df 
    

	#=PTDF_data = Dict() 
	for day_type in DAY_TYPES
		PTDF_data[day_type] = CSV.read(string(systemdir, "PTDF/fbdomain_$day_type.csv"), DataFrame) 
		rename!(PTDF_data[day_type],"ptdf_DE" => "ptdf_DE/LX")
	end

	PTDF_zones = names(PTDF_data[DAY_TYPES[1]])[38:end]
	PTDF_zones = replace.(PTDF_zones,"ptdf_" => "" )

	# replace "DE" name to "DE/AT/LX" 
	idx = findall(PTDF_zones.== "DE")
	if length(idx) > 0
		PTDF_zones[idx[1]] = "DE/LX" 
	end
    for day_type in DAY_TYPES 
		PTDF_data[day_type][!,:hubFrom] = convert.(String, PTDF_data[day_type][!,:hubFrom]) 
		PTDF_data[day_type][!,:hubTo] = convert.(String, PTDF_data[day_type][!,:hubTo])

		idx_1 = findall(isequal("DE"), PTDF_data[day_type].hubFrom)

		for i in idx_1
			PTDF_data[day_type].hubFrom[i] = "DE/LX"
		end
	
		idx_2 = findall(isequal("DE"), PTDF_data[day_type].hubTo)

		for i in idx_2
			PTDF_data[day_type].hubTo[i] = "DE/LX"
		end
	end

	from_zone = Dict()
	to_zone = Dict()
	#reserve_lines = Dict()
    
	for day_type in DAY_TYPES 
		from_zone[day_type] = Dict()
		to_zone[day_type] = Dict()
		#reserve_lines[day_type] = []
		
		for zone in PTDF_zones 
			from_zone[day_type][zone] = Dict()
			to_zone[day_type][zone] = Dict()
			for t in 1:T_hour
				from_zone[day_type][zone][t] = []
				to_zone[day_type][zone][t] = []
			end
		end
	end

	for day_type in DAY_TYPES  
		lines_set = union(findall(isequal("TieLine"), PTDF_data[day_type].elementType), findall(isequal("Tieline"), PTDF_data[day_type].elementType))
		for l in lines_set
			hub_1 = PTDF_data[day_type].hubFrom[l]
			hub_2 = PTDF_data[day_type].hubTo[l]
			t_hour = parse(Int64, PTDF_data[day_type][l, "dateTimeUtc"][12:13]) + 1
			if hub_1 in PTDF_zones && hub_2 in PTDF_zones
				#push!(reserve_lines[day_type], l)
				if PTDF_data[day_type].direction[l] == "DIRECT"
					push!(from_zone[day_type][hub_1][t_hour], l)
				else
					push!(to_zone[day_type][hub_2][t_hour], l)
				end
			end
		end
	end

	return PTDF_data, PTDF_zones, from_zone, to_zone#, reserve_lines
end =#

function get_associated_t(cne, day_type)
	return parse(Int64, PTDF_data[day_type][cne, "dateTimeUtc"][12:13]) + 1
end 

#= function get_mFRR_id(zone)
	id = findall(reserves.ZoneReserve.== zone)
	return id[end]
end =#

#= function load_net_positions(systemdir)
    net_positions = Dict()
    zones_ = ["CZ", "HR", "HU", "PL", "RO", "SI", "SK"] #	setdiff(PTDF_zones, zones) 
    #zones_ = setdiff(zones_, ["ALBE", "ALDE"])
	for day_type in DAY_TYPES
		net_positions[day_type] = Dict()
        for zone in zones_
            temp_net_pos = CSV.read(systemdir*"PTDF/net_positions/$day_type"*"_$zone"*"_net_position.csv", DataFrame)
            net_positions[day_type][zone] = zeros(24)
            for t in 1:24
                val = temp_net_pos[t,"Net position [MW]"]
                if val > 0
                    if temp_net_pos[t, 2] == "Import"
                        val = -val
                    end
                end
                net_positions[day_type][zone][t] = val
            end
              
        end        
	end

    return net_positions
end =#
end
#= function get_alpha(k, day_type, t_hour)
	alpha = Dict()

	for kP in reserve_lines[day_type]
		t_hourP = get_associated_t(kP, day_type)

		if t_hour == t_hourP
			hub_1 = PTDF_data[day_type].hubFrom[kP]
			hub_2 = PTDF_data[day_type].hubTo[kP]

            if PTDF_data[day_type].direction[kP] == "DIRECT"
				n = hub_1
				alpha[kP] = PTDF_data[day_type][k, "ptdf_"*n] 
			else
				n = hub_2
				alpha[kP] = -PTDF_data[day_type][k, "ptdf_"*n] 
			end
		end
	end

	return alpha
end =#