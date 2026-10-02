# .env
MEO_API_URL ?= http://192.168.100.131:7070

.PHONY: run

run:
	MEO_API_URL=$(MEO_API_URL) npm start
