using CSV
using DataFrames
using PlotlyJS
const scatter = PlotlyJS.scatter 
const savefig = PlotlyJS.savefig 
const Plot = PlotlyJS.Plot 

function plot_nodal_map(; savepath::String = "/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/results/nodal_map_interactive.html")

    buses_path = "/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/Data/Core/Buses.csv"
    lines_path = "/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/Data/Core/Lines.csv"
    flows_path = "/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/results/line_flows.csv"
    energy_path = "/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/results/energy_price.csv"

    buses = CSV.read(buses_path, DataFrame)
    lines = CSV.read(lines_path, DataFrame)

    # Φόρτωση flows (αν υπάρχει)
    flow_df = isfile(flows_path) ? CSV.read(flows_path, DataFrame) : DataFrame(Line=String[], Time=Int[], Flow=Float64[], Limit=Float64[])
    overloaded_lines = Set{String}()
    for row in eachrow(flow_df)
        if ismissing(row.Limit) || ismissing(row.Flow)
            continue
        end
        if abs(row.Flow) ≥ row.Limit
            push!(overloaded_lines, row.Line)
        end
    end

    # Φόρτωση μέσης τιμής ενέργειας ανά κόμβο (εφόσον υπάρχει)
    avg_price_map = Dict{String, Float64}()
    if isfile(energy_path)
        energy_df = CSV.read(energy_path, DataFrame)
        grouped = groupby(energy_df, :zone)
        for g in grouped
            avg_price_map[string(g.zone[1])] = mean(skipmissing(g.value))
        end
    end

    coord_map = Dict(row.Bus => (row.longitude, row.latitude) for row in eachrow(buses))
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

    unique_countries = unique(buses.Country)

    color_list = [
        "red", "blue", "green", "orange", "purple", "cyan", "magenta", "brown",
        "pink", "gray", "olive", "teal", "gold", "darkgreen", "navy", "coral",
        "lime", "darkblue", "chocolate", "turquoise", "indigo", "maroon", "silver",
        "plum", "salmon", "beige", "orchid", "steelblue"
    ]

    country_color = Dict{String, String}()
    for (i, c) in enumerate(unique_countries)
        color = color_list[(i - 1) % length(color_list) + 1]
        country_color[string(c)] = color
    end

    node_trace = []

    for country in unique_countries
        df = filter(row -> row.Country == country, buses)

            hover_texts = [
        haskey(avg_price_map, string(row.Bus)) ?
            string(row.Bus, "\n", round(avg_price_map[string(row.Bus)], digits=2)) :
            string(row.Bus)
        for row in eachrow(df)
    ]


            push!(node_trace, scatter(
                x = df.longitude,
                y = df.latitude,
                mode = "markers",
                marker = attr(size = 6, color = country_color[country]),
                name = country,
                hovertext = hover_texts,
                hoverinfo = "text"
            ))
        end

        layout = Layout(
            title = "Nodal map",
            xaxis = attr(title = "Longitude", showgrid = false),
            yaxis = attr(title = "Latitude", showgrid = false),
            width = 1000,
            height = 800
        )

        plot_data = vcat(line_traces..., node_trace...)
        plot_obj = Plot(plot_data, layout)

        isdir(dirname(savepath)) || mkpath(dirname(savepath))
        savefig(plot_obj, savepath)
        println("✅ Ο χάρτης αποθηκεύτηκε στο: $savepath")
    end


function plot_energy_price(csv_path::String)
    if !isfile(csv_path)
        return
    end

    df = CSV.read(csv_path, DataFrame)
    out_dir = "/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/results/Plots/Energy_prices"
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
    end
end

##################################################
#### 3. Αυτόματη Εκτέλεση όταν γίνεται include
##################################################

try
    plot_nodal_map()
    plot_energy_price("/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/results/energy_price.csv")
catch
end
