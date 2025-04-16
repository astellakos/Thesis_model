using CSV, DataFrames
using Dates

"""
    get_max_memory_usage_MB()

Επιστρέφει τη μνήμη RAM (σε MB) που χρησιμοποιεί αυτή τη στιγμή η Julia διεργασία,
χρησιμοποιώντας `ps` system command.
"""
function get_max_memory_usage_MB()
    pid = getpid()
    try
        output = read(`ps -o rss= -p $pid`, String)
        return round(parse(Int, strip(output)) / 1024; digits=2)  # KB → MB
    catch e
        @warn "Αποτυχία μέτρησης RAM με ps: $e"
        return missing
    end
end

