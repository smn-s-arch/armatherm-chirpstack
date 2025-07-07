# armatherm-chirpstack

## Post-Install-Anleitung

### MQTT testen

Führe folgende Befehle aus, um die MQTT-Verbindung zu testen:

```bash
mosquitto_sub -h <HOST_IP> -t "test/topic"
mosquitto_pub -h <HOST_IP> -t "test/topic" -m "hello"
```

Falls die Verbindung nicht funktioniert, überprüfe die Konfigurationsdatei unter:

```
/etc/mosquitto/mosquitto.conf
```

Folgende Einträge sollten vorhanden sein:

```
listener 1883
allow_anonymous true
```
Wenn nicht, müssen diese eingefügt werden.

---

## To-Dos in der ChirpStack Web-Oberfläche

1. **Admin-Benutzer anlegen**
2. **Standard-Admin deaktivieren**
3. **Gateway erstellen**
4. **Application erstellen**
5. **Integration zu ThingsBoard konfigurieren**
6. **Devices hinzufügen**
