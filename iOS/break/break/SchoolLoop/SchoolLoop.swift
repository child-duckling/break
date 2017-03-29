//
//  SchoolLoop.swift
//  break
//
//  Created by Saagar Jha on 1/18/16.
//  Copyright © 2016 Saagar Jha. All rights reserved.
//

import Foundation
import UIKit

@objc(SchoolLoop)
class SchoolLoop: NSObject, NSCoding {
	static var sharedInstance = SchoolLoop()
	let keychain = SchoolLoopKeychain.sharedInstance

	var school: SchoolLoopSchool!
	var schools: [SchoolLoopSchool] = []
	var account: SchoolLoopAccount!
	var courses: [SchoolLoopCourse] = []
	var computableCourses: [SchoolLoopComputableCourse] = []
	var assignments: [SchoolLoopAssignment] = []
	var assignmentsWithDueDates: [Date: [SchoolLoopAssignment]] {
		get {
			var awdd: [Date: [SchoolLoopAssignment]] = [:]
			for assigment in assignments {
				var assignmentsForDate = awdd[assigment.dueDate] ?? []
				assignmentsForDate.append(assigment)
				awdd[assigment.dueDate] = assignmentsForDate
			}
			return awdd
		}
	}
	var loopMail: [SchoolLoopLoopMail] = []
	var news: [SchoolLoopNews] = []
	var locker: SchoolLoopLockerItem!

	var currentTokens: [String] = []
	var currentName = ""
	var currentPath = ""
	var currentType = SchoolLoopLockerItemType.unknown

	private override init() {
		super.init()
	}

	required init?(coder aDecoder: NSCoder) {
		let schoolLoop = SchoolLoop.sharedInstance
		schoolLoop.school = aDecoder.decodeObject(forKey: "school") as? SchoolLoopSchool
		schoolLoop.schools = aDecoder.decodeObject(forKey: "schools") as? [SchoolLoopSchool] ?? []
		schoolLoop.account = aDecoder.decodeObject(forKey: "account") as? SchoolLoopAccount
		schoolLoop.courses = aDecoder.decodeObject(forKey: "courses") as? [SchoolLoopCourse] ?? []
		schoolLoop.assignments = aDecoder.decodeObject(forKey: "assignments") as? [SchoolLoopAssignment] ?? []
		schoolLoop.loopMail = aDecoder.decodeObject(forKey: "loopMail") as? [SchoolLoopLoopMail] ?? []
		schoolLoop.news = aDecoder.decodeObject(forKey: "news") as? [SchoolLoopNews] ?? []
		super.init()
	}

	func encode(with aCoder: NSCoder) {
		aCoder.encode(school, forKey: "school")
		aCoder.encode(schools, forKey: "schools")
		aCoder.encode(account, forKey: "account")
		aCoder.encode(courses, forKey: "courses")
		aCoder.encode(assignments, forKey: "assignments")
		aCoder.encode(loopMail, forKey: "loopMail")
		aCoder.encode(news, forKey: "news")
	}

	func getSchools(withCompletionHandler completionHandler: ((_ error: SchoolLoopError) -> Void)?) {
		let url = SchoolLoopConstants.schoolURL()
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		let session = URLSession.shared
		session.dataTask(with: request) { (data, response, error) in
			var newSchools: [SchoolLoopSchool] = []
			guard error == nil else {
				completionHandler?(.networkError)
				return
			}
			guard let data = data,
				let dataJSON = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [AnyObject] else {
					completionHandler?(.parseError)
					return
			}
			guard let schoolsJSON = dataJSON else {
				completionHandler?(.parseError)
				return
			}
			for schoolJSON in schoolsJSON {
				guard let schoolJSON = schoolJSON as? [String: AnyObject] else {
					completionHandler?(.parseError)
					return
				}
				let name = schoolJSON["name"] as? String ?? ""
				let domainName = schoolJSON["domainName"] as? String ?? ""
				let school = SchoolLoopSchool(name: name, domainName: domainName)
				newSchools.append(school)
			}
			self.schools = newSchools
			completionHandler?(.noError)
		}.resume()
	}

	func logIn(withSchoolName schoolName: String, username: String, password: String, completionHandler: ((_ error: SchoolLoopError) -> Void)?) {
		guard let school = school(forName: schoolName) else {
			completionHandler?(.doesNotExistError)
			return
		}
		self.school = school
		self.account = SchoolLoopAccount(username: username, password: password, fullName: account?.fullName ?? "", studentID: account?.studentID ?? "", hashedPassword: account?.hashedPassword ?? "")
		let url = SchoolLoopConstants.logInURL(withDomainName: school.domainName)
		let request = authenticatedRequest(withURL: url)
		let session = URLSession.shared
		session.dataTask(with: request) { (data, response, error) in
			guard error == nil else {
				completionHandler?(.networkError)
				return
			}
			let httpResponse = response as? HTTPURLResponse
			if httpResponse?.statusCode != 200 {
				#if os(iOS)
					Logger.log("Login failed with status code \(String(describing: httpResponse?.statusCode)))")
					Logger.log("Login username: \(username)")
					Logger.log("Login password size: \(password.characters.count)")
				#endif
				completionHandler?(.unknownError)
				return
			}
			guard let data = data,
				let dataJSON = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: AnyObject] else {
					completionHandler?(.parseError)
					return
			}
			guard let loginJSON = dataJSON else {
				completionHandler?(.parseError)
				return
			}
			let fullName = loginJSON["fullName"] as? String ?? ""
			let studentID = loginJSON["userID"] as? String ?? ""
			let hashedPassword = loginJSON["hashedPassword"] as? String ?? ""
			self.account = SchoolLoopAccount(username: username, password: password, fullName: fullName, studentID: studentID, hashedPassword: hashedPassword)
			self.account.loggedIn = true
			completionHandler?(.noError)
		}.resume()
	}

	func logOut() {
		_ = keychain.removePassword(forUsername: account.username)
		SchoolLoop.sharedInstance = SchoolLoop()
	}

	func getCourses(withCompletionHandler completionHandler: ((_ updatedCourses: [SchoolLoopCourse], _ error: SchoolLoopError) -> Void)?) {
		let url = SchoolLoopConstants.courseURL(withDomainName: school.domainName, studentID: account.studentID)
		let request = authenticatedRequest(withURL: url)
		let session = URLSession.shared
		session.dataTask(with: request) { (data, response, error) in
			var newCourses: [SchoolLoopCourse] = []
			var updatedCourses = [SchoolLoopCourse]()
			guard error == nil else {
				completionHandler?(updatedCourses, .networkError)
				return
			}
			guard let data = data,
				let dataJSON = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [AnyObject] else {
					completionHandler?(updatedCourses, .parseError)
					return
			}
			guard let coursesJSON = dataJSON else {
				completionHandler?(updatedCourses, .parseError)
				return
			}
			for courseJSON in coursesJSON {
				guard let courseJSON = courseJSON as? [String: AnyObject] else {
					completionHandler?(updatedCourses, .parseError)
					return
				}
				let courseName = courseJSON["courseName"] as? String ?? ""
				let period = courseJSON["period"] as? String ?? ""
				let teacherName = courseJSON["teacherName"] as? String ?? ""
				let grade = courseJSON["grade"] as? String ?? ""
				let score = courseJSON["score"] as? String ?? ""
				let periodID = courseJSON["periodID"] as? String ?? ""
				let lastUpdated = courseJSON["lastUpdated"] as? String ?? ""
				let course = SchoolLoopCourse(courseName: courseName, period: period, teacherName: teacherName, grade: grade, score: score, periodID: periodID)
				_ = course.set(newLastUpdated: lastUpdated)
				if let oldCourse = self.course(forPeriodID: periodID) {
					if oldCourse.set(newLastUpdated: lastUpdated) {
						updatedCourses.append(course)
					}
				} else {
					updatedCourses.append(course)
				}
				_ = course.set(newLastUpdated: lastUpdated)
				newCourses.append(course)
			}
			self.courses = newCourses
			completionHandler?(updatedCourses, .noError)
		}.resume()
	}

	func getGrades(withPeriodID periodID: String, completionHandler: ((_ error: SchoolLoopError) -> Void)?) {
		let url = SchoolLoopConstants.gradeURL(withDomainName: school.domainName, studentID: account.studentID, periodID: periodID)
		let request = authenticatedRequest(withURL: url)
		let session = URLSession.shared
		session.dataTask(with: request) { (data, response, error) in
			guard error == nil else {
				completionHandler?(.networkError)
				return
			}
			guard let course = self.course(forPeriodID: periodID) else {
				completionHandler?(.doesNotExistError)
				return
			}
			course.categories.removeAll()
			course.grades.removeAll()
			course.trendScores.removeAll()
			guard let data = data,
				let dataJSON = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [AnyObject] else {
					completionHandler?(.parseError)
					return
			}
			guard let categoriesJSON = (dataJSON?.first as? [String: AnyObject])?["categories"] as? [AnyObject] else {
				completionHandler?(.parseError)
				return
			}
			for categoryJSON in categoriesJSON {
				guard let categoryJSON = categoryJSON as? [String: AnyObject] else {
					completionHandler?(.parseError)
					return
				}
				let name = categoryJSON["name"] as? String ?? ""
				let score = categoryJSON["score"] as? String ?? ""
				let weight = categoryJSON["weight"] as? String ?? ""
				let category = SchoolLoopCategory(name: name, score: score, weight: weight)
				course.categories.append(category)

			}
			guard let GradingScaleJSON = (dataJSON?.first as? [String: AnyObject])?["GradingScale"] as? [String: AnyObject], let CutoffsJSON = GradingScaleJSON["Cutoffs"] as? [AnyObject] else {
				completionHandler?(.parseError)
				return
			}
			for CutoffJSON in CutoffsJSON {
				guard let CutoffJSON = CutoffJSON as? [String: AnyObject] else {
					completionHandler?(.parseError)
					return
				}
				let Name = CutoffJSON["Name"] as? String ?? ""
				let Start = CutoffJSON["Start"] as? String ?? ""
				let cutoff = SchoolLoopCutoff(Name: Name, Start: Start)
				course.cutoffs.append(cutoff)

			}
			guard let gradesJSON = (dataJSON?.first as? [String: AnyObject])?["grades"] as? [AnyObject] else {
				completionHandler?(.parseError)
				return
			}
			for gradeJSON in gradesJSON {
				guard let gradeJSON = gradeJSON as? [String: AnyObject] else {
					completionHandler?(.parseError)
					return
				}
				let percentScore = gradeJSON["percentScore"] as? String ?? ""
				let score = gradeJSON["score"] as? String ?? ""
				let comment = gradeJSON["comment"] as? String ?? ""
				let changedDate = gradeJSON["changedDate"] as? String ?? ""
				guard let assignmentJSON = gradeJSON["assignment"] as? [String: AnyObject] else {
					completionHandler?(.parseError)
					return
				}
				let title = assignmentJSON["title"] as? String ?? ""
				let categoryName = assignmentJSON["categoryName"] as? String ?? ""
				let maxPoints = assignmentJSON["maxPoints"] as? String ?? ""
				let systemID = assignmentJSON["systemID"] as? String ?? ""
				let dueDate = assignmentJSON["dueDate"] as? String ?? ""
				let grade = SchoolLoopGrade(title: title, categoryName: categoryName, percentScore: percentScore, score: score, maxPoints: maxPoints, comment: comment, systemID: systemID, dueDate: dueDate, changedDate: changedDate)
				course.grades.append(grade)
			}
			guard let trendScoresJSON = (dataJSON?.first as? [String: AnyObject])?["trendScores"] as? [AnyObject] else {
				completionHandler?(.trendScoreError)
				return
			}
			for trendScoreJSON in trendScoresJSON {
				guard let trendScoreJSON = trendScoreJSON as? [String: AnyObject] else {
					completionHandler?(.parseError)
					return
				}
				let score = trendScoreJSON["score"] as? String ?? ""
				let dayID = trendScoreJSON["dayID"] as? String ?? ""
				let trendScore = SchoolLoopTrendScore(score: score, dayID: dayID)
				course.trendScores.append(trendScore)
			}
			completionHandler?(.noError)
		}.resume()
	}

	func getAssignments(withCompletionHandler completionHandler: ((_ updatedAssignments: [SchoolLoopAssignment], _ error: SchoolLoopError) -> Void)?) {
		let url = SchoolLoopConstants.assignmentURL(withDomainName: school.domainName, studentID: account.studentID)
		let request = authenticatedRequest(withURL: url)
		let session = URLSession.shared
		session.dataTask(with: request) { (data, response, error) in
			var newAssignments: [SchoolLoopAssignment] = []
			var updatedAssignments = [SchoolLoopAssignment]()
			guard error == nil else {
				completionHandler?(updatedAssignments, .networkError)
				return
			}
			guard let data = data,
				let dataJSON = try? JSONSerialization.jsonObject(with: data, options: .allowFragments
				) as? [AnyObject] else {
					completionHandler?(updatedAssignments, .parseError)
					return
			}
			guard let assignmentsJSON = dataJSON else {
				completionHandler?(updatedAssignments, .parseError)
				return
			}
			for assignmentJSON in assignmentsJSON {
				guard let assignmentJSON = assignmentJSON as? [String: AnyObject] else {
					completionHandler?(updatedAssignments, .parseError)
					return
				}
				let title = assignmentJSON["title"] as? String ?? ""
				let description = assignmentJSON["description"] as? String ?? ""
				let courseName = assignmentJSON["courseName"] as? String ?? ""
				let dueDate = assignmentJSON["dueDate"] as? String ?? ""
				let iD = assignmentJSON["iD"] as? String ?? ""
				var links = [(title: String, URL: String)]()
				if let linksJSON = assignmentJSON["links"] as? [AnyObject] {
					for linkJSON in linksJSON {
						guard let linkJSON = linkJSON as? [String: AnyObject] else {
							completionHandler?(updatedAssignments, .parseError)
							return
						}
						let title = linkJSON["Title"] as? String ?? ""
						let URL = linkJSON["URL"] as? String ?? ""
						links.append((title: title, URL: URL))
					}
				}
				let assignment = SchoolLoopAssignment(title: title, assignmentDescription: description, courseName: courseName, dueDate: dueDate, links: links, iD: iD)
				if let oldAssignment = self.assignment(foriD: iD) {
					assignment.isCompleted = oldAssignment.isCompleted
				} else {
					updatedAssignments.append(assignment)
				}
				newAssignments.append(assignment)
			}
			self.assignments = newAssignments
			completionHandler?(updatedAssignments, .noError)
		}.resume()
	}

	func getLoopMail(withCompletionHandler completionHandler: ((_ updatedLoopMail: [SchoolLoopLoopMail], _ error: SchoolLoopError) -> Void)?) {
		let url = SchoolLoopConstants.loopMailURL(withDomainName: school.domainName, studentID: account.studentID)
		let request = authenticatedRequest(withURL: url)
		let session = URLSession.shared
		session.dataTask(with: request) { (data, response, error) in
			var newLoopMail: [SchoolLoopLoopMail] = []
			var updatedLoopMail = [SchoolLoopLoopMail]()
			guard error == nil else {
				completionHandler?(updatedLoopMail, .networkError)
				return
			}
			guard let data = data,
				let dataJSON = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [AnyObject] else {
					completionHandler?(updatedLoopMail, .parseError)
					return
			}
			guard let loopMailJSON = dataJSON else {
				completionHandler?(updatedLoopMail, .parseError)
				return
			}
			for loopMailJSON in loopMailJSON {
				guard let loopMailJSON = loopMailJSON as? [String: AnyObject] else {
					completionHandler?(updatedLoopMail, .parseError)
					return
				}
				let subject = loopMailJSON["subject"] as? String ?? ""
				let date = loopMailJSON["date"] as? String ?? ""
				let ID = loopMailJSON["ID"] as? String ?? ""
				guard let senderJSON = loopMailJSON["sender"] as? [String: AnyObject] else {
					completionHandler?(updatedLoopMail, .parseError)
					return
				}
				let name = senderJSON["name"] as? String ?? ""
				let id = senderJSON["userID"] as? String ?? ""
				let sender = SchoolLoopContact(id: id, name: name, role: "", desc: "")
				let loopMail = SchoolLoopLoopMail(subject: subject, sender: sender, date: date, ID: ID)
				if self.loopMail(forID: ID) == nil {
					updatedLoopMail.append(loopMail)
				}
				newLoopMail.append(loopMail)
			}
			self.loopMail = newLoopMail
			completionHandler?(updatedLoopMail, .noError)
		}.resume()
	}

	func getLoopMailMessage(withID ID: String, completionHandler: ((_ error: SchoolLoopError) -> Void)?) {
		let url = SchoolLoopConstants.loopMailMessageURL(withDomainName: school.domainName, studentID: account.studentID, ID: ID)
		let request = authenticatedRequest(withURL: url)
		let session = URLSession.shared
		session.dataTask(with: request) { (data, response, error) in
			guard error == nil else {
				completionHandler?(.networkError)
				return
			}
			guard let loopMail = self.loopMail(forID: ID) else {
				completionHandler?(.doesNotExistError)
				return
			}
			guard let data = data,
				let dataJSON = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: AnyObject] else {
					completionHandler?(.parseError)
					return
			}
			guard let messageJSON = dataJSON else {
				completionHandler?(.parseError)
				return
			}
			let message = messageJSON["message"] as? String ?? ""
			var links = [(title: String, URL: String)]()
			if let linksJSON = messageJSON["links"] as? [AnyObject] {
				for linkJSON in linksJSON {
					guard let linkJSON = linkJSON as? [String: AnyObject] else {
						completionHandler?(.parseError)
						return
					}
					let title = linkJSON["Title"] as? String ?? ""
					let URL = linkJSON["URL"] as? String ?? ""
					links.append((title: title, URL: URL))
				}
			}
			loopMail.message = message
			loopMail.links = links
			completionHandler?(.noError)
		}.resume()
	}

	func getLoopMailContacts(withQuery query: String, completionHandler: ((_ contacts: [SchoolLoopContact], _ error: SchoolLoopError) -> Void)?) {
		let url = SchoolLoopConstants.loopMailContactsURL(withDomainName: school.domainName, studentID: account.studentID, query: query)
		let request = authenticatedRequest(withURL: url)
		let session = URLSession.shared
		session.dataTask(with: request) { (data, response, error) in
			var contacts: [SchoolLoopContact] = []
			guard error == nil else {
				completionHandler?(contacts, .networkError)
				return
			}
			guard let data = data,
				let dataJSON = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [AnyObject] else {
					completionHandler?(contacts, .parseError)
					return
			}
			guard let contactsJSON = dataJSON else {
				completionHandler?(contacts, .parseError)
				return
			}
			for contactJSON in contactsJSON {
				guard let contactJSON = contactJSON as? [String: AnyObject] else {
					completionHandler?(contacts, .parseError)
					return
				}
				let id = contactJSON["id"] as? String ?? ""
				let name = contactJSON["name"] as? String ?? ""
				let role = contactJSON["role"] as? String ?? ""
				let desc = contactJSON["desc"] as? String ?? ""
				let contact = SchoolLoopContact(id: id, name: name, role: role, desc: desc)
				contacts.append(contact)
			}
			completionHandler?(contacts, .noError)
		}.resume()
	}

	func sendLoopMail(withComposedLoopMail composedLoopMail: SchoolLoopComposedLoopMail, completionHandler: ((_ error: SchoolLoopError) -> Void)?) {
		let url = SchoolLoopConstants.loopMailSendURL(withDomainName: school.domainName)
		var request = hashedAuthenticatedRequest(withURL: url)
		modifyForSending(&request, withComposedLoopMail: composedLoopMail)
		let session = URLSession.shared
		session.dataTask(with: request) { (data, response, error) in
			guard error == nil else {
				completionHandler?(.networkError)
				return
			}
			completionHandler?(.noError)
		}.resume()
	}

	func getNews(withCompletionHandler completionHandler: ((_ updatedNews: [SchoolLoopNews], _ error: SchoolLoopError) -> Void)?) {
		let url = SchoolLoopConstants.newsURL(withDomainName: school.domainName, studentID: account.studentID)
		let request = authenticatedRequest(withURL: url)
		let session = URLSession.shared
		session.dataTask(with: request) { (data, response, error) in
			var newNews: [SchoolLoopNews] = []
			var updatedNews = [SchoolLoopNews]()
			guard error == nil else {
				completionHandler?(updatedNews, .networkError)
				return
			}
			guard let data = data,
				let dataJSON = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [AnyObject] else {
					completionHandler?(updatedNews, .parseError)
					return
			}
			guard let newsJSON = dataJSON else {
				completionHandler?(updatedNews, .parseError)
				return
			}
			for newsJSON in newsJSON {
				guard let newsJSON = newsJSON as? [String: AnyObject] else {
					completionHandler?(updatedNews, .parseError)
					return
				}
				let title = newsJSON["title"] as? String ?? ""
				let authorName = newsJSON["authorName"] as? String ?? ""
				let createdDate = newsJSON["createdDate"] as? String ?? ""
				let description = newsJSON["description"] as? String ?? ""
				let iD = newsJSON["iD"] as? String ?? ""
				var links = [(title: String, URL: String)]()
				if let linksJSON = newsJSON["links"] as? [AnyObject] {
					for linkJSON in linksJSON {
						guard let linkJSON = linkJSON as? [String: AnyObject] else {
							completionHandler?(updatedNews, .parseError)
							return
						}
						let title = linkJSON["Title"] as? String ?? ""
						let URL = linkJSON["URL"] as? String ?? ""
						links.append((title: title, URL: URL))
					}
				}
				let news = SchoolLoopNews(title: title, authorName: authorName, createdDate: createdDate, newsDescription: description, links: links, iD: iD)
				if self.news(foriD: iD) == nil {
					updatedNews.append(news)
				}
				newNews.append(news)
			}
			self.news = newNews
			completionHandler?(updatedNews, .noError)
		}.resume()
	}

	func getLocker(withPath path: String, completionHandler: ((_ error: SchoolLoopError) -> Void)?) {
		let url = SchoolLoopConstants.lockerURL(withPath: path, domainName: school.domainName, username: account.username)
		let request = authenticatedRequest(withURL: url, httpMethod: "PROPFIND")
		let session = URLSession.shared
		session.dataTask(with: request) { (data, response, error) in
			guard let data = data else {
				completionHandler?(.parseError)
				return
			}
			let parser = XMLParser(data: data)
			parser.delegate = self
			if !parser.parse() {
				completionHandler?(.parseError)
				return
			} else {
				completionHandler?(.noError)
			}
		}.resume()
	}

	func authenticatedRequest(withURL url: URL, httpMethod: String = "GET") -> URLRequest {
		let request = NSMutableURLRequest(url: url)
		request.httpMethod = httpMethod

		let plainString = "\(account.username):\(account.password)"
		guard let base64Data = (plainString as NSString).data(using: String.Encoding.utf8.rawValue) else {
			assertionFailure("Could not encode plainString")
			return request as URLRequest
		}
		let base64String = base64Data.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0))
		request.addValue("Basic \(base64String)", forHTTPHeaderField: "Authorization")
		return request as URLRequest
	}

	func hashedAuthenticatedRequest(withURL url: URL, httpMethod: String = "POST") -> URLRequest {
		let request = NSMutableURLRequest(url: url)
		request.httpMethod = httpMethod

		let plainString = "\(account.username):\(account.hashedPassword)"
		guard let base64Data = (plainString as NSString).data(using: String.Encoding.utf8.rawValue) else {
			assertionFailure("Could not encode plainString")
			return request as URLRequest
		}
		let base64String = base64Data.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0))
		request.addValue("Basic \(base64String)", forHTTPHeaderField: "Authorization")
		request.addValue("true", forHTTPHeaderField: "SL-HASH")
		request.addValue(SchoolLoopConstants.devToken, forHTTPHeaderField: "SL-UUID")
		return request as URLRequest
	}

	func modifyForSending(_ request: inout URLRequest, withComposedLoopMail composedLoopMail: SchoolLoopComposedLoopMail) {
		request.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Content-Type")
		request.httpBody = try? JSONSerialization.data(withJSONObject: ["to": composedLoopMail.to.map({ $0.id }).joined(separator: " "), "cc": composedLoopMail.cc.map({ $0.id }).joined(separator: " "), "subject": composedLoopMail.subject, "message": composedLoopMail.message], options: [])
	}

	func school(forName name: String) -> SchoolLoopSchool? {
		for school in schools {
			if school.name == name {
				return school
			}
		}
		return nil
	}

	func course(forPeriodID periodID: String) -> SchoolLoopCourse? {
		for course in courses {
			if course.periodID == periodID {
				return course
			}
		}
		return nil
	}

	func assignment(foriD iD: String) -> SchoolLoopAssignment? {
		for assignment in assignments {
			if assignment.iD == iD {
				return assignment
			}
		}
		return nil
	}

	func loopMail(forID ID: String) -> SchoolLoopLoopMail? {
		for loopMail in self.loopMail {
			if loopMail.ID == ID {
				return loopMail
			}
		}
		return nil
	}

	func news(foriD iD: String) -> SchoolLoopNews? {
		for news in self.news {
			if news.iD == iD {
				return news
			}
		}
		return nil
	}

	func lockerItemParent(forPath path: String) -> SchoolLoopLockerItem? {
		let cleanPath = path.hasSuffix("/") ? path.substring(to: (path.range(of: "/", options: .backwards)?.lowerBound)!) : path
		var currentLockerItem: SchoolLoopLockerItem? = locker
		var currentDirectoryContents: [SchoolLoopLockerItem] = locker?.lockerItems ?? []
		for (index, pathComponent) in cleanPath.components(separatedBy: "/").enumerated().dropFirst().dropLast() {
			for lockerItem in currentDirectoryContents {
				if lockerItem.path.components(separatedBy: "/").dropFirst()[index] == pathComponent {
					currentLockerItem = lockerItem
					currentDirectoryContents = lockerItem.lockerItems
					break
				}
				currentLockerItem = nil
			}
		}
		return currentLockerItem
	}

	func lockerItem(forPath path: String) -> SchoolLoopLockerItem? {
		guard let parent = lockerItemParent(forPath: path) else {
			return nil
		}
		for lockerItem in parent.lockerItems {
			if lockerItem.path == path {
				return lockerItem
			}
		}
		return nil
	}

	func file(forLockerItem lockerItem: SchoolLoopLockerItem) -> URL {
		let session = URLSession.shared
		let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(lockerItem.name)
		session.synchronousDataTask(withRequest: request(forLockerItemPath: lockerItem.path)
		) { (data, response, error) in
			try? data?.write(to: file)
		}
		return file
	}

	func request(forLockerItemPath path: String) -> URLRequest {
		return authenticatedRequest(withURL: SchoolLoopConstants.lockerURL(withPath: path, domainName: school.domainName, username: account.username))
	}
}

extension SchoolLoop: XMLParserDelegate {
	func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
		currentTokens.append(elementName)
	}

	func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
		if currentTokens.last == "d:collection" {
			currentType = .directory
		} else if currentTokens.last == "d:response" {
			let lockerItem = SchoolLoopLockerItem(name: currentName, path: currentPath, type: currentType)
			if let parent = lockerItemParent(forPath: lockerItem.path) {
				if !parent.lockerItems.contains(where: { $0 == lockerItem }) {
					parent.lockerItems.append(lockerItem)
				}
			} else {
				locker = lockerItem
			}
			currentName = ""
			currentPath = ""
			currentType = .unknown
		}
		_ = currentTokens.popLast()
	}

	func parser(_ parser: XMLParser, foundCharacters string: String) {
		if currentTokens.last == "d:href" {
			currentPath = string.substring(from: string.index(string.characters.index(of: "/")!, offsetBy: 1))
			currentPath = currentPath.substring(from: currentPath.index(currentPath.characters.index(of: "/")!, offsetBy: 1))
			currentPath = currentPath.substring(from: currentPath.characters.index(of: "/")!)
		} else if currentTokens.last == "d:displayname" {
			currentName += string
		} else if currentTokens.last == "d:getcontenttype" {
			if currentType != .directory {
				if string == "application/pdf" {
					currentType = .pdf
				} else {
					currentType = .unknown
				}
			}
		}
	}
}

extension URLSession {
	func synchronousDataTask(withRequest request: URLRequest, completionHandler: (Data?, URLResponse?, Error?) -> Void) {
		var data: Data?, response: URLResponse?, error: Error?
		let semaphore = DispatchSemaphore(value: 0)
		dataTask(with: request) {
			data = $0
			response = $1
			error = $2
			semaphore.signal()
		}.resume()
		_ = semaphore.wait(timeout: DispatchTime.distantFuture)
		completionHandler(data, response, error)
	}
}