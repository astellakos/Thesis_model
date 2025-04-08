using DataFrames, CSV

function calculate_and_save_flows(PTDF_df::DataFrame, Lines_df::DataFrame, model::Model, save_path::String)

    println("🚀 Υπολογισμός ροών μεταφοράς από μεταβλητές r[zone, t]...")

    # Ανάγνωση PTDF δεδομένων
    buses = names(PTDF_df)[2:end] 
    line_ids = PTDF_df.Line
    T_15 = maximum(index -> index[2], keys(model[:r]))  # βρίσκουμε max t από τα keys

    # Υπολογισμός flows
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
                    0.0  # σε περίπτωση που λείπει κάποιο bus,t
                end
                flow_t += ptdf * r_val 
            end
            push!(flow_df, (line, t, flow_t, limit_val))
        end
    end

    filepath = joinpath(save_path, "line_flows.csv")
    CSV.write(filepath, flow_df)
    println("💾 Οι ροές αποθηκεύτηκαν στο: $filepath")
end



