
#export UR_DBI_NO_COMMIT=1

workflow ns start \
    --debug "echo" \
    test1.xml \
    "model input string=abracadabra321" \
    "sleep time=1"


