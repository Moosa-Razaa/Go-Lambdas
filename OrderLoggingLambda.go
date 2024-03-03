package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
)

type Order struct {
	Name        string  `json:"Name"`
	Description string  `json:"Description"`
	CreatedAt   string  `json:"CreatedAt"`
	Status      *string `json:"Status"`
}

type Response struct {
	Message string `json:"Answer"`
}

func HandleSQSEvent(ctx context.Context, sqsEvent events.SQSEvent) error {
	log.Printf("Order logging lambda invoked...")

	for _, record := range sqsEvent.Records {
		log.Printf("Iterating on SQS records.")
		var order Order
		log.Printf("Record Body: " + record.Body)
		if unmarshalError := json.Unmarshal([]byte(record.Body), &order); unmarshalError != nil {
			order.Status = aws.String("Error converting object")
			return fmt.Errorf("error in logging: %v", unmarshalError)
		}

		logMessage := fmt.Sprintf("\nOrder Name: %s\nOrder Description: %s\nOrder CreatedAt: %s\nOrder Status: %s\n",
			order.Name, order.Description, order.CreatedAt, aws.StringValue(order.Status))

		log.Printf("Order received: " + logMessage)
	}

	log.Printf("Task completed!")
	return nil
}

func main() {
	lambda.Start(HandleSQSEvent)
}
