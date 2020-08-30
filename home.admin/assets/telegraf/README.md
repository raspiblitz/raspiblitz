[telegraf](https://www.influxdata.com/time-series-platform/telegraf/) is a metric collection tool by influxData.
It is opensource and works fine with [influxDB](https://www.influxdata.com/products/influxdb-overview/) as the timeseries database and [Grafana](https://grafana.com/grafana/) as the graphics front end.

You may take a look [here](https://github.com/gcgarner/IOTstack) for a nice dockerized installation of influxDB and Grafana on a raspberry pi.

Make sure to have a telegraf section in your `/mnt/hdd/raspiblitz.conf`
you have to manually edit them into `/mnt/hdd/raspiblitz.conf` before calling
```
sudo /home/admin/config.scripts/bonus.telegraf.sh on
```

You have to provide a running influxDB / Grafana infrastructure elsewhere (reachable for your RaspiBlitz)

# telegraf section for raspiblitz.conf
All telegraf switches and configuration variables. You may copy & paste them into your RaspiBlitz configuration at `/mnt/hdd/raspiblitz.conf`, after editing and provide the proper values matching your environment

```
# switch telegraf service and metrics capturing on/off
telegrafMonitoring=on
#
# the full url to your influxDB data ingestion point, with port
telegrafInfluxUrl='http://192.168.2.46:8086'
#
# the name of your influxDB database
telegrafInfluxDatabase='raspiblitz'
#
# credentials for this database
telegrafInfluxUsername='telegraf'
telegrafInfluxPassword='metricsmetricsmetricsmetrics'
```

# Grafana dashboard for RaspiBlitz
