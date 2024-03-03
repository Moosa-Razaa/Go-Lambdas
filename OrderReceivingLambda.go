package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
)

type Order struct {
	Name        string  `json:"Name"`
	Description string  `json:"Description"`
	CreatedAt   string  `json:"CreatedAt"`
	Status      *string `json:"Status"`
}

func HandleLambdaEvent(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	queueURL := os.Getenv("QUEUE_URL")
	log.Printf("Order receiving lambda invoked...")

	if queueURL == "" {
		log.Println("Error: QUEUE_URL environment variable is not set.")
		return events.APIGatewayProxyResponse{
			StatusCode: 503,
			Headers: map[string]string{
				"Content-Type": "application/json",
			},
			Body: string("Queue url is missing from environment variable."),
		}, fmt.Errorf("QUEUE_URL environment variable is not set")
	}

	var order Order
	log.Printf("Body: " + request.Body)
	if unmarshalRequestBodyError := json.Unmarshal([]byte(request.Body), &order); unmarshalRequestBodyError != nil {
		log.Printf("Error unmarshalling body: %v", unmarshalRequestBodyError)
		return events.APIGatewayProxyResponse{
			StatusCode: 400,
			Body:       "Bad Request",
		}, nil
	}

	sess, err := session.NewSession()
	if err != nil {
		log.Printf("Error creating AWS session: %v", err)
		return events.APIGatewayProxyResponse{
			StatusCode: 503,
			Headers: map[string]string{
				"Content-Type": "application/json",
			},
			Body: string("Can't create AWS sessions."),
		}, err
	}

	sqsClient := sqs.New(sess)
	receivedOrder := "From OrderLoggingLambda"
	order.Status = &receivedOrder

	messageBody := fmt.Sprintf(`{"Name": "%s", "Description": "%s", "CreatedAt": "%s", "Status": "%s"}`,
		order.Name, order.Description, order.CreatedAt, *order.Status)

	sendMessageInput := &sqs.SendMessageInput{
		MessageBody:  aws.String(messageBody),
		QueueUrl:     aws.String(queueURL),
		DelaySeconds: aws.Int64(0),
	}

	log.Printf("Sending message to SQS: " + messageBody)

	_, err = sqsClient.SendMessage(sendMessageInput)
	if err != nil {
		log.Printf("Error sending message to SQS: %v", err)
		return events.APIGatewayProxyResponse{
			StatusCode: 503,
			Headers: map[string]string{
				"Content-Type": "application/json",
			},
			Body: string("Can't send message to SQS."),
		}, err
	}

	response := events.APIGatewayProxyResponse{
		StatusCode: 200,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: string("Order Received Successfully!"),
	}

	return response, nil
}

func main() {
	lambda.Start(HandleLambdaEvent)
}
