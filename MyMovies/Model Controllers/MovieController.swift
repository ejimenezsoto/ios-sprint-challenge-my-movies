//
//  MovieController.swift
//  MyMovies
//
//  Created by Spencer Curtis on 8/17/18.
//  Copyright © 2018 Lambda School. All rights reserved.
//

import Foundation
import CoreData

enum NetworkError: Error {
    case noIdentifier
    case otherError
    case noData
    case failedEncode
    case failedDecode
    
}

class MovieController {
    
    private let apiKey = "4cc920dab8b729a619647ccc4d191d5e"
    private let baseURL = URL(string: "https://api.themoviedb.org/3/search/movie")!
    
    let firebaseURL = URL(string: "https://movie-3eb21.firebaseio.com/")!
    
    typealias CompletionHandler = (Result<Bool, NetworkError>) -> Void
    
    // MARK: - Properties
    
    var searchedMovies: [MovieDBMovie] = []
    
    // MARK: - TheMovieDB API
    
    func searchForMovie(with searchTerm: String, completion: @escaping CompletionHandler) {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        let queryParameters = ["query": searchTerm,
                               "api_key": apiKey]
        components?.queryItems = queryParameters.map({URLQueryItem(name: $0.key, value: $0.value)})
        
        guard let requestURL = components?.url else {
            completion(.failure(.otherError))
            return
        }
        
        URLSession.shared.dataTask(with: requestURL) { (data, _, error) in
            if let error = error {
                NSLog("Error searching for movie with search term \(searchTerm): \(error)")
                completion(.failure(.otherError))
                return
            }
            
            guard let data = data else {
                NSLog("No data returned from data task")
                completion(.failure(.noData))
                return
            }
            
            do {
                let movieDBMovies = try JSONDecoder().decode(MovieDBResults.self, from: data).results
                self.searchedMovies = movieDBMovies
                completion(.success(true))
            } catch {
                NSLog("Error decoding JSON data: \(error)")
                completion(.failure(.failedDecode))
            }
        }.resume()
    }
    
    
    // MARK: - Core Data
    
    func fetchMoviesFromServer(completion: @escaping CompletionHandler = { _ in }) {
        let requestURL = firebaseURL.appendingPathExtension("json")
        
        URLSession.shared.dataTask(with: requestURL) { data, _, error in
            if let error = error {
                NSLog("Error fetching movies: \(error)")
                completion(.failure(.otherError))
                return
            }
            
            guard let data = data else {
                NSLog("No data returned from fetch")
                completion(.failure(.noData))
                return
            }
            
            do {
                let movieRepresentations = Array(try JSONDecoder().decode([String : MovieRepresentation].self, from: data).values)
                try self.updateMovies(with: movieRepresentations)
                completion(.success(true))
            } catch {
                NSLog("Error decoding movies from server: \(error)")
                completion(.failure(.failedDecode))
            }
        }.resume()
    }
    
    func sendMovieToServer(movie: Movie, completion: @escaping CompletionHandler = { _ in }) {
        guard let uuid = movie.identifier else {
            completion(.failure(.noIdentifier))
            return
        }
        
        let requestURL = firebaseURL.appendingPathComponent(uuid.uuidString).appendingPathExtension("json")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "PUT"
        
        do {
            guard let representation = movie.movieRepresentation else {
                completion(.failure(.failedEncode))
                return
            }
            request.httpBody = try JSONEncoder().encode(representation)
        } catch {
            NSLog("Error encoding movie \(movie): \(error)")
            completion(.failure(.failedEncode))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                NSLog("Error sending movie to server: \(error)")
                completion(.failure(.otherError))
                return
            }
            
            completion(.success(true))
        }.resume()
    }
    
    func deleteMovieFromServer(_ movie: Movie, completion: @escaping CompletionHandler = { _ in }) {
        guard let uuid = movie.identifier else {
            completion(.failure(.noIdentifier))
            return
        }
        
        let requestURL = firebaseURL.appendingPathComponent(uuid.uuidString).appendingPathExtension("json")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "DELETE"
        
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                NSLog("Error deleting movie from server: \(movie): \(error)")
                completion(.failure(.otherError))
                return
            }
            
            completion(.success(true))
        }.resume()
    }
    
    private func updateMovies(with representations: [MovieRepresentation]) throws {
        let identifiersToFetch = representations.compactMap { UUID(uuidString: $0.identifier) }
        let representationsByID = Dictionary(uniqueKeysWithValues: zip(identifiersToFetch, representations))
        var moviesToCreate = representationsByID
        
        let fetchRequest: NSFetchRequest<Movie> = Movie.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "identifier IN %@", identifiersToFetch)
        
        let context = CoreDataStack.shared.container.newBackgroundContext()
        
        var error: Error?
        
        context.performAndWait {
            do {
                let existingMovies = try context.fetch(fetchRequest)
                
                for movie in existingMovies {
                    guard let id = movie.identifier,
                        let representation = representationsByID[id] else { continue }
                    
                    self.update(movie: movie, with: representation)
                    moviesToCreate.removeValue(forKey: id)
                }
            } catch let fetchError {
                error = fetchError
            }
            
            for representation in moviesToCreate.values {
                Movie(movieRepresentation: representation, context: context)
            }
        }
        
        if let error = error { throw error }
        
        try CoreDataStack.shared.save(context: context)
    }
    
    private func update(movie: Movie, with representation: MovieRepresentation) {
        movie.title = representation.title
        movie.hasWatched = representation.hasWatched
    }
}


