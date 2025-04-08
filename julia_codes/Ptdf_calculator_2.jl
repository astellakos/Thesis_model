using CSV, DataFrames, LinearAlgebra

function compute_PTDF(Buses::DataFrame, Lines::DataFrame, Ref_hub::DataFrame, save_path::String)
    buses_data = deepcopy(Buses)
    lines_data = deepcopy(Lines)

    # Αφαίρεση απομονωμένων κόμβων 
    connected_buses = unique(vcat(lines_data.FromBus, lines_data.ToBus))
    disconnected_buses = setdiff(buses_data.Bus, connected_buses)
    buses_data = filter(row -> row.Bus ∈ connected_buses, buses_data)

    # Δημιουργία λιστών
    buses = buses_data.Bus
    lines = lines_data.Line
    nb = length(buses)
    nl = length(lines)

    # Πίνακας A (incidence) 
    A = zeros(Float64, nl, nb)
    for (i, row) in enumerate(eachrow(lines_data))
        from_idx = findfirst(==(row.FromBus), buses)
        to_idx = findfirst(==(row.ToBus), buses)
        if from_idx !== nothing
            A[i, from_idx] = -1.0
        end
        if to_idx !== nothing
            A[i, to_idx] = 1.0
        end
    end

    # Πίνακας Bd
    X = lines_data.Reactance
    Bd = Diagonal(1.0 ./ X)

    # Υπολογισμός PTDF 
    T = A' * Bd * A
    PTDF = Bd * A * inv(T)

    # Δημιουργία PTDF DataFrame (χωρίς ref node)
    PTDF_df = DataFrame(Line = lines)
    for bus in buses
        PTDF_df[!, Symbol(bus)] = PTDF[:, findfirst(==(bus), buses)]
    end

    # Προσθήκη απομονωμένων κόμβων (με μηδενικά)
    for dbus in disconnected_buses
        PTDF_df[!, Symbol(dbus)] = zeros(Float64, nl)
    end

    # Αποθήκευση 
    CSV.write(joinpath(save_path, "PTDF_matrix_theoretical.csv"), PTDF_df)
    CSV.write(joinpath(save_path, "A_matrix_new.csv"), DataFrame(A, Symbol.(string.(buses))))
    CSV.write(joinpath(save_path, "Bd_matrix.csv"), DataFrame(Matrix(Bd), :auto))

    # Info
    println("✅ Ο πίνακας PTDF υπολογίστηκε και αποθηκεύτηκε.")
    println("📌 Reference node: ", Ref_hub.Bus)
    if !isempty(disconnected_buses)
        println("🔌 Απομονωμένοι κόμβοι που προστέθηκαν με μηδενικά: ", disconnected_buses)
    end
end

# === Αυτό εκτελείται αυτόματα όταν κάνεις include ===
compute_PTDF(Buses, Lines, Ref_hub, PATH_global * "/results/ptdf_calc/")

