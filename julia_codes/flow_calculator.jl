using DataFrames, CSV

function calculate_and_save_flows(PTDF_df::DataFrame, Lines_df::DataFrame, model::Model, save_path::String; verbose::Bool=true)

    buses = names(PTDF_df)[2:end]
    line_ids = PTDF_df.Line
    T_15 = maximum(index -> index[2], keys(model[:r]))

    flow_df = DataFrame(Line = String[], Time = Int[], Flow = Float64[], Limit = Float64[])

    for (i, line) in enumerate(line_ids)
        limit = Lines_df[Lines_df.Line .== line, :FlowLimitForw]
        limit_val = isempty(limit) ? missing : limit[1]

        for t in 1:T_15
            flow_t = 0.0
            for bus in buses
                ptdf = PTDF_df[i, bus]
                r_val = try
                    value(model[:r][bus, t])
                catch
                    0.0
                end
                flow_t += ptdf * r_val
            end
            push!(flow_df, (line, t, flow_t, limit_val))
        end
    end

    # Save full flows
    filepath = joinpath(save_path, "line_flows.csv")
    CSV.write(filepath, flow_df)

    # Identify binding constraints
    ε = 1e-3
    binding_df = filter(row -> 
        !ismissing(row.Limit) && abs(abs(row.Flow) - row.Limit) ≤ ε,
        flow_df)

    # Save full binding data
    filepath2 = joinpath(save_path, "binding_constraints.csv")
    CSV.write(filepath2, binding_df)

    # Summary per time
    summary_df = combine(groupby(binding_df, :Time), nrow => :NumBindingLines)
    filepath3 = joinpath(save_path, "binding_constraints_summary.csv")
    CSV.write(filepath3, summary_df)

    # Compute stats
    total_bindings = nrow(binding_df)
    total_possibilities = length(line_ids) * T_15
    binding_percentage = total_bindings / total_possibilities * 100

    if verbose
        println("🔒 Saved binding constraints to: $filepath2")
        println("📊 Saved summary of binding constraints to: $filepath3")
        println("🔒 Total binding constraints: $total_bindings / $total_possibilities")
        println("📈 Binding percentage: ", round(binding_percentage, digits=2), "%")
    end
end
