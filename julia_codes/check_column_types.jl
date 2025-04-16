# check_column_types.jl (έξυπνη αναγνώριση delimiter)
using CSV, DataFrames

function detect_delimiter(filepath::String)::Char
    open(filepath, "r") do io
        first_line = readline(io)
        if count(==(','), first_line) > count(==(';'), first_line)
            return ','
        else
            return ';'
        end
    end
end

function check_column_types(filepath::String; sample_rows=5)
    delim = detect_delimiter(filepath)
    println("\n📂 Έλεγχος αρχείου: $filepath (με delimiter = '$delim')")

    df = CSV.read(filepath, DataFrame; delim=delim, silencewarnings=true)

    println("\n▶ Έλεγχος τύπου στηλών:")
    for col in names(df)
        col_data = df[!, col]
        col_type = eltype(col_data)

        if col_type == String
            sample = col_data[1:min(end, sample_rows)]
            num_count = count(x -> tryparse(Float64, x) !== nothing, sample)

            if num_count / length(sample) >= 0.8
                println("⚠ \"$col\" διαβάστηκε ως String, αλλά οι περισσότερες τιμές μοιάζουν με αριθμούς.")
            else
                println("ℹ \"$col\" => String (δεν μοιάζει με αριθμούς)")
            end
        else
            println("✅ \"$col\" => $(col_type)")
        end
    end
end

# === Εκτέλεση από χρήστη === #
println("\n🔧 Πληκτρολόγησε το path του .csv που θες να ελέγξεις:")
filepath = String(strip(readline()))

if isempty(filepath)
    println("❌ Δεν δόθηκε αρχείο. Τερματισμός.")
else
    check_column_types(filepath)
end
