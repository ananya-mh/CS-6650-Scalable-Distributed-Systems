package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

type Product struct {
	ID          int    `json:"id"`
	Name        string `json:"name"`
	Category    string `json:"category"`
	Description string `json:"description"`
	Brand       string `json:"brand"`
}

type SearchResponse struct {
	Products   []Product `json:"products"`
	TotalFound int       `json:"total_found"`
	SearchTime string    `json:"search_time"`
}

var (
	products   []Product
	categories = []string{"Electronics", "Books", "Home", "Clothing", "Sports", "Toys", "Beauty", "Garden", "Automotive", "Health"}
	brands     = []string{"Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Sigma", "Omega"}
)

func generateProducts(count int) {
	products = make([]Product, count)
	for i := 0; i < count; i++ {
		brand := brands[i%len(brands)]
		category := categories[i%len(categories)]
		products[i] = Product{
			ID:          i + 1,
			Name:        fmt.Sprintf("Product %s %d", brand, i+1),
			Category:    category,
			Description: fmt.Sprintf("Description for Product %s %d", brand, i+1),
			Brand:       brand,
		}
	}
}

// searchHandler processes ?q=<text> requests
func searchHandler(w http.ResponseWriter, r *http.Request) {
	query := strings.ToLower(r.URL.Query().Get("q"))
	if query == "" {
		http.Error(w, "Missing query parameter 'q'", http.StatusBadRequest)
		return
	}

	start := time.Now()
	matches := []Product{}
	totalFound := 0
	checked := 0

	// Each search checks exactly 100 products
	for _, p := range products {
		if checked >= 100 {
			break
		}
		checked++

		// case-insensitive match in name or category
		if strings.Contains(strings.ToLower(p.Name), query) ||
			strings.Contains(strings.ToLower(p.Category), query) {
			totalFound++
			if len(matches) < 20 {
				matches = append(matches, p)
			}
		}
	}

	duration := time.Since(start).Seconds()

	response := SearchResponse{
		Products:   matches,
		TotalFound: totalFound,
		SearchTime: fmt.Sprintf("%.3fs", duration),
	}

	w.Header().Set("Content-Type", "application/json")

	// Marshal with indentation
	indentedJSON, err := json.MarshalIndent(response, "", "  ")
	if err != nil {
		http.Error(w, "Failed to encode response", http.StatusInternalServerError)
		return
	}

	w.Write(indentedJSON)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func main() {
	fmt.Println("Generating products...")
	generateProducts(100000)
	fmt.Println("Generated 100,000 products")
	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/products/search", searchHandler)
	http.ListenAndServe(":8080", nil)
}