//
//  SupportRatingsReviewsTableViewController.swift
//  break
//
//  Created by Saagar Jha on 9/5/17.
//  Copyright © 2017 Saagar Jha. All rights reserved.
//

import MessageUI
import StoreKit
import UIKit

class SupportRatingsReviewsTableViewController: UITableViewController, SKStoreProductViewControllerDelegate, MFMailComposeViewControllerDelegate {

	override func viewDidLoad() {
		super.viewDidLoad()

		// Uncomment the following line to preserve selection between presentations
		// self.clearsSelectionOnViewWillAppear = false

		// Uncomment the following line to display an Edit button in the navigation bar for this view controller.
		// self.navigationItem.rightBarButtonItem = self.editButtonItem()
		setupSelfAsDetailViewController()
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
		viewController.dismiss(animated: true, completion: nil)
	}

	func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
		controller.dismiss(animated: true, completion: nil)
	}

	// MARK: - Table view data source

	override func numberOfSections(in tableView: UITableView) -> Int {
		if #available(iOS 10.3, *) {
			return 3
		} else {
			return 2
		}
	}

	/*
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return 0
    }
	*/

	/*
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "reuseIdentifier", for: indexPath)

        // Configure the cell...

        return cell
    }
    */

	/*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

	/*
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

	/*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

	/*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		switch indexPath.section {
		case 0:
			let device = UIDevice.current
			let composeViewController = MFMailComposeViewController()
			composeViewController.mailComposeDelegate = self
			composeViewController.setToRecipients(["support+break@saagarjha.com"])
			composeViewController.setSubject("break Support Request")
			composeViewController.setMessageBody("""
			Hi,
			
			I'm having some issues with break:
			
			
			[insert your issue here]
			
			
			Just for reference, I'm using an \(SchoolLoopConstants.devOS) running \(device.systemName) \(device.systemVersion).
			
			I'd really appreciate it if you could take a look at this issue!
			
			Thanks.
			""", isHTML: false)
			composeViewController.addAttachmentData(Data(Logger.readLog().utf8), mimeType: "text/plain", fileName: "log.txt")
			present(composeViewController, animated: true, completion: nil)
		case 1:
			let productViewController = SKStoreProductViewController()
			productViewController.delegate = self
			productViewController.loadProduct(withParameters: [SKStoreProductParameterITunesItemIdentifier: breakConstants.iTunesIdentifier], completionBlock: nil)
			present(productViewController, animated: true, completion: nil)
		case 2:
			if #available(iOS 10.3, *) {
				SKStoreReviewController.requestReview()
			}
		default:
			assertionFailure("Invalid ratings and review index")
		}
		tableView.deselectRow(at: indexPath, animated: true)
	}

	/*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
