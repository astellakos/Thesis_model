using CSV
using DataFrames
using PlotlyJS
using Dates
using Statistics
using XLSX
using Printf
using Colors
const scatter = PlotlyJS.scatter 
const savefig = PlotlyJS.savefig 
const Plot = PlotlyJS.Plot

function plot_nodal_maps(model::Model, line_flows::DataFrame, energy_price::DataFrame, Ref_hub::DataFrame, custom_save_dir::Union{String, Nothing}=nothing)

    buses = vcat(deepcopy(Buses), Ref_hub)
    lines = deepcopy(Lines)
    flows = deepcopy(line_flows)
    energy = deepcopy(energy_price)

    coord_map = Dict(row.Bus => (row.longitude, row.latitude) for row in eachrow(buses))

    energy_map = Dict{Tuple{String, Int}, Float64}()
    if nrow(energy) > 0
        for row in eachrow(energy)
            energy_map[(string(row.zone), row.time)] = row.value
        end
    end

    # Χειροκίνητη ανάθεση χρωμάτων (15 χώρες)
    country_color = Dict(
        "France" => "#7f7f7f",      # gray
        "Germany" => "#e377c2",     # pink
        "Belgium" => "#1f77b4",     # blue
        "Netherland" => "#17becf",  # cyan
        "Austria" => "#2ca02c",     # green
        "Czech" => "#d62728",       # red
        "Poland" => "#9467bd",      # purple
        "Slovakia" => "#bcbd22",    # lime
        "Hungary" => "#8c564b",     # brown
        "Slovenia" => "#ff7f0e",    # orange
        "Croatia" => "#ff9896",     # light red
        "Switzerland" => "#c5b0d5", # light purple
        "Luxemburg" => "#98df8a",   # light green
        "Denmark" => "#ffbb78",     # light orange
        "Romania" => "#aec7e8"      # light blue
    )

    save_dir = isnothing(custom_save_dir) ? joinpath(PATH_global, "results", "nodal_maps_t") : joinpath(custom_save_dir, "nodal_maps_t")
    isdir(save_dir) || mkpath(save_dir)

    for t in 1:96
        ε = 1e-3
        overloaded_lines = Set{String}()
        for row in eachrow(flows)
            if row.Time == t && !ismissing(row.Limit) && !ismissing(row.Flow) &&
               abs(abs(row.Flow) - row.Limit) ≤ ε
                push!(overloaded_lines, row.Line)
            end
        end

        load_per_node = Dict{String, Float64}()
        renewable_per_node = Dict{String, Float64}()

        for row in eachrow(buses)
            zone = string(row.Bus)
            load_val = try value(model[:load_zone][zone, t]) catch; 0.0 end
            load_per_node[zone] = 0.25 * load_val

            renewable_generation = 0.0
            for g in get(generators_id_per_zone["renewable"], zone, [])
                val = try value(model[:p_re][g, t]) catch; 0.0 end
                renewable_generation += 0.25 * val
            end
            renewable_per_node[zone] = renewable_generation
        end

        load_values = collect(values(load_per_node))
        min_load = minimum(load_values)
        max_load = maximum(load_values)

        line_traces = []
        for row in eachrow(lines)
            from, to = row.FromBus, row.ToBus
            if haskey(coord_map, from) && haskey(coord_map, to)
                x = [coord_map[from][1], coord_map[to][1]]
                y = [coord_map[from][2], coord_map[to][2]]
                is_overloaded = row.Line in overloaded_lines

                push!(line_traces, scatter(
                    x = x, y = y,
                    mode = "lines",
                    line = attr(
                        color = is_overloaded ? "black" : "gray",
                        width = is_overloaded ? 3 : 1.5
                    ),
                    hoverinfo = "none",
                    showlegend = false
                ))
            end
        end

        node_traces = []
        unique_countries = unique(buses.Country)
        for country in unique_countries
            df = filter(row -> row.Country == country, buses)

            node_sizes = [
                max_load == min_load ? 6 : 4 + 8 * (load_per_node[string(row.Bus)] - min_load) / (max_load - min_load)
                for row in eachrow(df)
            ]

            node_colors = [
                get(country_color, string(country), "#cccccc")
                for row in eachrow(df)
            ]

            hover_texts = []
            for row in eachrow(df)
                zone = string(row.Bus)
                fuel_gen = 0.0
                for g in get(generators_id_per_zone["conventional"], zone, [])
                    val = try value(model[:p][g, t]) catch; 0.0 end
                    fuel_gen += 0.25 * val
                end
                renew_gen = renewable_per_node[zone]
                ls = try value(model[:ls][zone, t]) * 0.25 catch; 0.0 end
                net = try value(model[:r][zone, t]) * 0.25 catch; 0.0 end
                load = load_per_node[zone]
                price_val = haskey(energy_map, (zone, t)) ? round(energy_map[(zone, t)], digits=2) : "-"

                push!(hover_texts,
                    "$zone, P: $price_val, FG: $(round(fuel_gen, digits=2)), RE: $(round(renew_gen, digits=2)), LS: $(round(ls, digits=2)), NP: $(round(net, digits=2)), LD: $(round(load, digits=2))"
                )
            end

            push!(node_traces, scatter(
                x = df.longitude,
                y = df.latitude,
                mode = "markers",
                marker = attr(
                    size = node_sizes,
                    color = node_colors,
                    opacity = 0.95,
                    line = attr(width = 0)
                ),
                name = country,
                hovertext = hover_texts,
                hoverinfo = "text"
            ))
        end

        layout = Layout(
            title = "Nodal Map t = $t",
            xaxis = attr(title = "Longitude", showgrid = false, zeroline = false),
            yaxis = attr(title = "Latitude", showgrid = false, zeroline = false),
            width = 1000,
            height = 700,
            paper_bgcolor = "rgb(230,236,247)",
            plot_bgcolor = "rgb(230,236,247)",
            hovermode = "closest"
        )

        plot_data = vcat(line_traces..., node_traces...)
        plot_obj = Plot(plot_data, layout)

        open("/dev/null", "w") do devnull
            redirect_stderr(devnull) do
                try
                    savefig(plot_obj, joinpath(save_dir, "nodal_map_t$t.html"))
                catch
                end
            end
        end
    end
end


function plot_energy_price(csv_path::String, alt_path::Union{Nothing, String}=nothing)
    if !isfile(csv_path)
        return
    end

    df = CSV.read(csv_path, DataFrame)
    out_dir = "/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/results/Plots/Energy_prices"
    alt_out_dir = alt_path === nothing ? nothing : joinpath(alt_path, "Energy_prices")
    if alt_out_dir !== nothing && !isdir(alt_out_dir)
        mkpath(alt_out_dir)
    end

    isdir(out_dir) || mkpath(out_dir)

    for file in readdir(out_dir)
        if endswith(file, ".html")
            rm(joinpath(out_dir, file))
        end
    end

    zones = unique(df.zone)

    for zone in zones
        df_zone = filter(:zone => z -> z == zone, df)

        if nrow(df_zone) == 0
            continue
        end

        plt = Plot(
            scatter(x = df_zone.time, y = df_zone.value, mode = "lines", name = zone),
            Layout(
                title = "Τιμή Ενέργειας - $zone",
                xaxis = attr(title = "Χρονική περίοδος"),
                yaxis = attr(title = "Τιμή (€/MWh)")
            )
        )

        filename = joinpath(out_dir, "energy_price_$zone.html")
        savefig(plt, filename)
        if alt_out_dir !== nothing
            alt_filename = joinpath(alt_out_dir, "energy_price_$zone.html")
            savefig(plt, alt_filename)
        end        
    end
end

try
    plot_nodal_map()
    plot_energy_price("/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/results/energy_price.csv")
catch
end

function log_run_metrics(
    model::Model,
    day_type::String,
    target_countries::Vector{String},
    model_solve_time::Float64,
    total_time::Float64,
    memory_allocated_MB::Float64
)

    log_file_csv = joinpath(PATH_global, "results", "run_log.csv")

    values = [
    join(target_countries, "/"),
    day_type,
    string(num_variables(model)),
    string(num_constraints(model; count_variable_in_set_constraints=true)),
    replace(@sprintf("%.3f", model_solve_time), "." => ","),
    replace(@sprintf("%.3f", total_time), "." => ","),
    replace(@sprintf("%.2f", memory_allocated_MB), "." => ",")
]


    quoted_row = join(["\"$val\"" for val in values], ";")

    if !isfile(log_file_csv)
        open(log_file_csv, "w") do io
            write(io, "countries;day_type;num_variables;num_constraints;model_solve_time_sec;total_time_sec;memory_MB;memory_allocated_MB\n")
            write(io, quoted_row * "\n")
        end
    else
        open(log_file_csv, "r+") do io
            seekend(io)
            filesize = position(io)
            seek(io, max(filesize - 2, 0))
            tail = read(io, String)
            if !endswith(tail, "\n")
                write(io, "\n")
            end
        end
        open(log_file_csv, "a") do io
            write(io, quoted_row * "\n")
        end
    end

    println("📒 Καταγράφηκαν τα στατιστικά του run στο CSV: $log_file_csv")
end
