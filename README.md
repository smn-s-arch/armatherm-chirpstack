# armatherm-chirpstack

after installation test mqtt with: 

mosquitto_sub -h <HOST_IP> -t "test/topic"
mosquitto_pub -h <HOST_IP> -t "test/topic" -m "hello"

If nothing is received lookup the configuration file /etc/mosuitto/mosquitto.conf
for entrys:
    listener 1883
    allow_anonymous true
