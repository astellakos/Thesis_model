using CSV, DataFrames, LinearAlgebra

# Ορισμός χωρών 
target_countries = ["Romania","Hungary"]
# Φόρτωση δεδομένων 
lines_data = CSV.read("/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/Data/Core/Lines.csv", DataFrame)
buses_data = CSV.read("/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/Data/Core/Buses.csv", DataFrame)

# Επιλογή κόμβων των χωρών 
buses_data = filter(row -> row.Country ∈ target_countries, buses_data)
Ref_hub = buses_data[1, :]  # Reference node
buses_data = buses_data[2:end, :]  # Αφαίρεση του reference node

# Επιλογή γραμμών: ενδοχώρα ή διασύνδεση μεταξύ των χωρών
country_prefixes = [split(b.Bus, "_")[1] for b in eachrow(buses_data)]
prefix_set = Set(country_prefixes)
lines_data = filter(row -> begin
    from_prefix = split(row.FromBus, "_")[1]
    to_prefix = split(row.ToBus, "_")[1]
    (from_prefix ∈ prefix_set && to_prefix ∈ prefix_set)
end, lines_data)

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
det_T = det(T)
println("🔎 Ορίζουσα του Aᵀ * Bd * A: ", det_T)

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
results_path = "/Users/alexiostellakos/Desktop/Thesis_model_V2_copy/results/ptdf_calc/"
CSV.write(results_path * "PTDF_matrix_theoretical_orig.csv", PTDF_df)
CSV.write(results_path * "A_matrix_new.csv", DataFrame(A, Symbol.(string.(buses))))
CSV.write(results_path * "Bd_matrix.csv", DataFrame(Matrix(Bd), :auto))

# Info
println("✅ Ο πίνακας PTDF υπολογίστηκε και αποθηκεύτηκε.")
println("📌 Reference node: ", Ref_hub.Bus)
if !isempty(disconnected_buses)
    println("🔌 Απομονωμένοι κόμβοι που προστέθηκαν με μηδενικά: ", disconnected_buses)
end
